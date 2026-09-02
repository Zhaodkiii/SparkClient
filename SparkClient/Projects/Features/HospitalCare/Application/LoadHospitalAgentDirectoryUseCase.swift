import Foundation

struct LoadHospitalAgentDirectoryUseCase: Sendable {
    let remoteAPI: any HospitalCareRemoteServing
    let catalogCache: HospitalCatalogMemoryCache
    let logger: any Logger = ConsoleLogger()

    /// CHAT-000055：科室目录 stale-while-revalidate——命中缓存先返回，过期时后台静默刷新；
    /// 刷新失败继续使用旧缓存。
    func loadDepartments(accountID: Int64, hospitalID: UUID) async throws -> [HospitalDepartmentSummary] {
        if let cached = catalogCache.departments(accountID: accountID, hospitalID: hospitalID) {
            if catalogCache.isDepartmentsStale(accountID: accountID, hospitalID: hospitalID) {
                scheduleRefreshDepartments(accountID: accountID, hospitalID: hospitalID)
            }
            return cached
        }
        return try await fetchAndStoreDepartments(accountID: accountID, hospitalID: hospitalID)
    }

    /// CHAT-000055：智能体目录 stale-while-revalidate——仅无筛选（无关键字、无科室）场景
    /// 使用缓存；命中先返回并后台静默刷新，失败回落缓存。
    func loadAgents(
        accountID: Int64,
        hospitalID: UUID,
        departmentID: UUID?,
        keyword: String,
        memberID: Int?
    ) async throws -> [HospitalAgentCard] {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let useCache = trimmedKeyword.isEmpty && departmentID == nil
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
            if useCache {
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
                if recentByAgent[item.agent.id] == nil {
                    recentByAgent[item.agent.id] = item.threadId
                }
            }
        }
        // CHAT-000054：服务端已为每位医生返回唯一已发布智能体，iOS 不再重复
        // 执行“选主”逻辑（published_at 选最新），直接消费服务端顺序。
        let cards = agents.map { dto in
            let threadID = recentByAgent[dto.id]
            return HospitalAgentCard(
                id: dto.id,
                hospitalID: dto.hospitalId,
                name: dto.name,
                publicSummary: dto.publicSummary ?? "",
                serviceBoundary: dto.serviceBoundary ?? "",
                doctorID: dto.doctor.id,
                doctorDisplayName: dto.doctor.displayName,
                doctorTitle: dto.doctor.title ?? "",
                doctorAvatarURL: dto.doctor.avatarUrl ?? "",
                specialties: dto.doctor.specialties ?? [],
                departmentID: dto.department?.id,
                departmentName: dto.department?.name ?? "",
                hasRecentConversation: threadID != nil,
                recentThreadID: threadID
            )
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
