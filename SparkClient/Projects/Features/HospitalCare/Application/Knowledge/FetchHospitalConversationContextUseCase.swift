import Foundation

/// CHAT-000055：进入医院会话时后台刷新完整 context（能力 + 知识 Manifest）。
///
/// Q22：context 是知识 Manifest 与会话能力的单一事实源；
/// Q27/Q28：下架/撤权状态只能由该回源结果驱动，禁止本地猜测。
struct FetchHospitalConversationContextUseCase {
    let remoteAPI: any HospitalCareRemoteServing

    struct Result: Equatable, Sendable {
        let capabilities: HospitalConversationCapabilities
        let manifest: HospitalAgentKnowledgeManifest?
        /// 服务端实时服务状态原始值（如 "doctor_joined"）；nil 表示服务端未下发，调用方不得猜测。
        let serviceStatus: String?
    }

    /// - Parameters:
    ///   - memberID: 非空时服务端一并校验成员归属（Q28 撤权校验）。
    /// - Returns: 404（非医院会话）返回 nil；撤权（MEMBER_ACCESS_DENIED）返回禁发能力；
    ///   其他错误上抛，由调用方决定阻断策略。
    func execute(threadID: UUID, memberID: Int? = nil) async throws -> Result? {
        let context: HospitalConversationContextDTO?
        do {
            context = try await remoteAPI.fetchConversationContext(threadID: threadID, memberID: memberID)
        } catch {
            if isMemberAccessDenied(error) {
                return Result(capabilities: .memberAccessRevoked, manifest: nil, serviceStatus: nil)
            }
            throw error
        }
        guard let context else { return nil }
        return Result(
            capabilities: Self.mapCapabilities(context.capabilities),
            manifest: context.knowledgeManifest.map(Self.mapManifest),
            serviceStatus: context.serviceStatus
        )
    }

    private func isMemberAccessDenied(_ error: Error) -> Bool {
        String(describing: error).contains("MEMBER_ACCESS_DENIED")
    }

    static func mapCapabilities(_ dto: HospitalConversationCapabilitiesDTO?) -> HospitalConversationCapabilities {
        guard let dto else { return .optimisticDefault }
        return HospitalConversationCapabilities(
            canReadCachedHistory: dto.canReadCachedHistory ?? true,
            canPullRemoteMessages: dto.canPullRemoteMessages ?? true,
            canSendMessage: dto.canSendMessage ?? true,
            canSyncKnowledge: dto.canSyncKnowledge ?? true,
            readOnlyReason: dto.readOnlyReason
        )
    }

    static func mapManifest(_ dto: HospitalKnowledgeManifestDTO) -> HospitalAgentKnowledgeManifest {
        HospitalAgentKnowledgeManifest(
            manifestRevision: dto.manifestRevision,
            generatedAt: dto.generatedAt,
            agentID: dto.agentId,
            hospitalID: dto.hospitalId,
            items: dto.knowledgeBases.map { item in
                HospitalKnowledgeManifestItem(
                    knowledgeBaseID: item.knowledgeBaseId,
                    name: item.name,
                    revision: item.revision,
                    vectorStatus: HospitalKnowledgeVectorStatus(rawOrUnknown: item.vectorStatus),
                    indexedRevision: item.indexedRevision,
                    updatedAt: item.updatedAt,
                    isDeleted: item.deleted ?? false
                )
            }
        )
    }
}
