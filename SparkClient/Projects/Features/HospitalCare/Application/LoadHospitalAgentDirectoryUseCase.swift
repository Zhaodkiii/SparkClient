import Foundation

struct LoadHospitalAgentDirectoryUseCase: Sendable {
    let remoteAPI: any HospitalCareRemoteServing
    let catalogCache: HospitalCatalogMemoryCache
    let logger: any Logger = ConsoleLogger()

    /// CHAT-000055：科室目录 stale-while-revalidate——命中缓存先返回，过期时后台静默刷新；
    /// 刷新失败继续使用旧缓存。
    /// `forceRefresh` 为 true 时跳过缓存读取直接回源（医院首页显式刷新使用），成功后会写入缓存。
    func loadDepartments(accountID: Int64, hospitalID: UUID, forceRefresh: Bool = false) async throws -> [HospitalDepartmentSummary] {
        if forceRefresh == false, let cached = catalogCache.departments(accountID: accountID, hospitalID: hospitalID) {
            if catalogCache.isDepartmentsStale(accountID: accountID, hospitalID: hospitalID) {
                scheduleRefreshDepartments(accountID: accountID, hospitalID: hospitalID)
            }
            return cached
        }
        return try await fetchAndStoreDepartments(accountID: accountID, hospitalID: hospitalID)
    }

    /// CHAT-000055：智能体目录 stale-while-revalidate——仅无筛选（无关键字、无科室）场景
    /// 使用缓存；命中先返回并后台静默刷新，失败回落缓存。
    /// `forceRefresh` 为 true 时跳过缓存读取直接回源（医院首页显式刷新使用），成功后写入缓存；
    /// 回源失败时调用方决定继续使用旧内容。
    func loadAgents(
        accountID: Int64,
        hospitalID: UUID,
        departmentID: UUID?,
        keyword: String,
        memberID: Int?,
        forceRefresh: Bool = false
    ) async throws -> [HospitalAgentCard] {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUnfiltered = trimmedKeyword.isEmpty && departmentID == nil
        let useCache = isUnfiltered && forceRefresh == false
        let agents: [HospitalAgentPublicDTO]
        if useCache, let cached = catalogCache.agents(accountID: accountID, hospitalID: hospitalID) {
            if catalogCache.isAgentsStale(accountID: accountID, hospitalID: hospitalID) {
                scheduleRefreshAgents(accountID: accountID, hospitalID: hospitalID)
            }
            agents = cached
        } else {
            do {
                agents = try await fetchAgents(hospitalID: hospitalID, departmentID: departmentID, keyword: trimmedKeyword)
            } catch {
                if useCache, let cached = catalogCache.agents(accountID: accountID, hospitalID: hospitalID) {
                    agents = cached
                } else {
                    throw error
                }
            }
            if isUnfiltered {
                catalogCache.storeAgents(agents, accountID: accountID, hospitalID: hospitalID)
            }
        }
        return try await makeCards(agents: agents, memberID: memberID)
    }

    private func fetchAgents(
        hospitalID: UUID,
        departmentID: UUID?,
        keyword: String
    ) async throws -> [HospitalAgentPublicDTO] {
        try await remoteAPI.listAgents(
            hospitalID: hospitalID,
            departmentID: departmentID,
            keyword: keyword,
            page: 1,
            pageSize: 50
        )
    }

    private func fetchAndStoreDepartments(accountID: Int64, hospitalID: UUID) async throws -> [HospitalDepartmentSummary] {
        let rows = try await remoteAPI.listDepartments(hospitalID: hospitalID).map {
            HospitalDepartmentSummary(id: $0.id, name: $0.name, sortOrder: $0.sortOrder ?? 0)
        }
        catalogCache.storeDepartments(rows, accountID: accountID, hospitalID: hospitalID)
        return rows
    }

    private func scheduleRefreshDepartments(accountID: Int64, hospitalID: UUID) {
        Task { [remoteAPI, catalogCache, logger] in
            do {
                let rows = try await remoteAPI.listDepartments(hospitalID: hospitalID).map {
                    HospitalDepartmentSummary(id: $0.id, name: $0.name, sortOrder: $0.sortOrder ?? 0)
                }
                catalogCache.storeDepartments(rows, accountID: accountID, hospitalID: hospitalID)
            } catch {
                logger.warning(
                    "hospital.directory.departments.refresh_failed error=\(error.localizedDescription)",
                    module: .general
                )
            }
        }
    }

    private func scheduleRefreshAgents(accountID: Int64, hospitalID: UUID) {
        Task { [remoteAPI, catalogCache, logger] in
            do {
                let agents = try await remoteAPI.listAgents(
                    hospitalID: hospitalID,
                    departmentID: nil,
                    keyword: "",
                    page: 1,
                    pageSize: 50
                )
                catalogCache.storeAgents(agents, accountID: accountID, hospitalID: hospitalID)
            } catch {
                logger.warning(
                    "hospital.directory.agents.refresh_failed error=\(error.localizedDescription)",
                    module: .general
                )
            }
        }
    }

    private func makeCards(
        agents: [HospitalAgentPublicDTO],
        memberID: Int?
    ) async throws -> [HospitalAgentCard] {
        var recentByAgent: [UUID: UUID] = [:]
        if let memberID {
            let conversations = (try? await remoteAPI.listConversations(memberID: memberID, page: 1, pageSize: 100)) ?? []
            for item in conversations {
                // 线上问诊会话不得作为医生智能体「继续咨询」的 recent。
                if item.consultation != nil { continue }
                if recentByAgent[item.agent.id] == nil {
                    recentByAgent[item.agent.id] = item.threadId
                }
            }
        }
        // CHAT-000054：服务端已为每位医生返回唯一已发布智能体，iOS 不再重复
        // 执行“选主”逻辑（published_at 选最新），直接消费服务端顺序。
        let cards = agents.map { dto in
            HospitalAgentCard(publicDTO: dto, recentThreadID: recentByAgent[dto.id])
        }
        // 已咨询优先的稳定分组：组内保持服务端返回顺序，不做额外排序。
        var consulted: [HospitalAgentCard] = []
        var others: [HospitalAgentCard] = []
        for card in cards {
            if card.hasRecentConversation {
                consulted.append(card)
            } else {
                others.append(card)
            }
        }
        return consulted + others
    }
}

/// 智能体头像地址：优先服务端解析后的 agent.avatar_url（专属或复用医生），
/// 为空时回退医生头像；再空由 UI 用名称首字兜底。
func resolvedAgentAvatarURL(_ dto: HospitalAgentPublicDTO) -> String {
    if let url = dto.avatarUrl, url.isEmpty == false {
        return url
    }
    return dto.doctor.avatarUrl ?? ""
}

extension HospitalAgentCard {
    /// 由公开目录/详情 DTO 构造卡片；问诊表单路由只带 agentID，回源后走这条映射。
    init(publicDTO dto: HospitalAgentPublicDTO, recentThreadID: UUID? = nil) {
        self.init(
            id: dto.id,
            hospitalID: dto.hospitalId,
            name: dto.name,
            publicSummary: dto.publicSummary ?? "",
            serviceBoundary: dto.serviceBoundary ?? "",
            doctorID: dto.doctor.id,
            doctorDisplayName: dto.doctor.displayName,
            doctorTitle: dto.doctor.title ?? "",
            doctorAvatarURL: dto.doctor.avatarUrl ?? "",
            avatarURL: resolvedAgentAvatarURL(dto),
            avatarVersion: dto.avatarVersion ?? "",
            specialties: dto.doctor.specialties ?? [],
            departmentID: dto.department?.id,
            departmentName: dto.department?.name ?? "",
            hasRecentConversation: recentThreadID != nil,
            recentThreadID: recentThreadID
        )
    }
}
