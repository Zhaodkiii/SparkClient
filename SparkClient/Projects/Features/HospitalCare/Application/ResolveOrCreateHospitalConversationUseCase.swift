import Foundation

struct ResolveOrCreateHospitalConversationUseCase {
    let remoteAPI: HospitalCareRemoteAPI
    let scopeStore: HospitalConversationScopeStore

    func execute(
        agentID: UUID,
        memberID: Int,
        hospitalID: UUID,
        accountID: Int64,
        recentThreadID: UUID?
    ) async throws -> UUID {
        if let recentThreadID {
            scopeStore.remember(
                HospitalConversationScope(
                    threadID: recentThreadID,
                    agentID: agentID,
                    memberID: memberID,
                    hospitalID: hospitalID
                ),
                accountID: accountID
            )
            return recentThreadID
        }
        let created = try await remoteAPI.createConversation(agentID: agentID, memberID: memberID)
        scopeStore.remember(
            HospitalConversationScope(
                threadID: created.threadId,
                agentID: agentID,
                memberID: memberID,
                hospitalID: created.conversation.hospital?.id ?? hospitalID
            ),
            accountID: accountID
        )
        return created.threadId
    }
}
