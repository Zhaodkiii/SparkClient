import Foundation

struct LoadHospitalDoctorProfileUseCase: Sendable {
    let remoteAPI: any HospitalCareRemoteServing
    let catalogCache: HospitalCatalogMemoryCache
    let logger: any Logger = ConsoleLogger()

    /// - Parameters:
    ///   - accountID: 用于命中账号级医院目录/医生详情缓存；为 nil 时直接回源。
    ///   - hospitalName: 调用方已知的医院名称快照，作为解析失败时的兜底展示。
    /// CHAT-000055：医生详情 stale-while-revalidate——命中缓存先返回并后台静默刷新，
    /// 无缓存且回源失败时上抛（由 View 展示加载失败与重试）。
    func execute(
        agentID: UUID,
        accountID: Int64? = nil,
        hospitalName: String = ""
    ) async throws -> HospitalDoctorLightProfile {
        let agent = try await resolveAgent(agentID: agentID, accountID: accountID)
        // CHAT-000054：医院资料按 hospital_id 从固定医院目录缓存解析，
        // 缓存未命中时统一走医院列表接口，不在 View 中拼第二个请求。
        let hospital = try? await resolveHospital(hospitalID: agent.hospitalId, accountID: accountID)
        return HospitalDoctorLightProfile(
            id: agent.doctor.id,
            agentID: agent.id,
            agentName: agent.name,
            hospitalName: hospital?.name ?? hospitalName,
            hospitalIntroduction: hospital?.introduction ?? "",
            departmentName: agent.department?.name ?? "",
            displayName: agent.doctor.displayName,
            title: agent.doctor.title ?? "",
            avatarURL: agent.doctor.avatarUrl ?? "",
            specialties: agent.doctor.specialties ?? [],
            introduction: agent.doctor.introduction ?? "",
            serviceBoundary: agent.serviceBoundary ?? "",
            publicationStatus: agent.publicationStatus ?? ""
        )
    }

    private func resolveAgent(agentID: UUID, accountID: Int64?) async throws -> HospitalAgentPublicDTO {
        if let accountID,
           let cached = catalogCache.agentDetail(agentID: agentID, accountID: accountID) {
            if catalogCache.isAgentDetailStale(agentID: agentID, accountID: accountID) {
                scheduleRefreshAgentDetail(agentID: agentID, accountID: accountID)
            }
            return cached
        }
        do {
            let agent = try await remoteAPI.fetchAgent(agentID: agentID)
            if let accountID {
                catalogCache.storeAgentDetail(agent, accountID: accountID)
            }
            return agent
        } catch {
            if let accountID,
               let cached = catalogCache.agentDetail(agentID: agentID, accountID: accountID) {
                return cached
            }
            throw error
        }
    }

    private func scheduleRefreshAgentDetail(agentID: UUID, accountID: Int64) {
        Task { [remoteAPI, catalogCache, logger] in
            do {
                let agent = try await remoteAPI.fetchAgent(agentID: agentID)
                catalogCache.storeAgentDetail(agent, accountID: accountID)
            } catch {
                logger.warning(
                    "hospital.doctor.detail.refresh_failed error=\(error.localizedDescription)",
                    module: .general
                )
            }
        }
    }

    private func resolveHospital(hospitalID: UUID, accountID: Int64?) async throws -> HospitalSummary? {
        if let accountID,
           let cached = catalogCache.hospitals(accountID: accountID),
           let match = cached.first(where: { $0.id == hospitalID }) {
            return match
        }
        let hospitals = try await remoteAPI.listHospitals(page: 1, pageSize: 100).map {
            HospitalSummary(
                id: $0.id,
                code: $0.code ?? "",
                name: $0.name,
                shortName: $0.shortName ?? "",
                introduction: $0.introduction ?? "",
                status: $0.status
            )
        }
        if let accountID {
            catalogCache.storeHospitals(hospitals, accountID: accountID)
        }
        return hospitals.first(where: { $0.id == hospitalID })
    }
}
