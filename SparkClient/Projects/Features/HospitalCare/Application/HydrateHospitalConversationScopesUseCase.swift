import Foundation

/// CHAT-000054：登录/切换账号后批量回填全部医院 Thread 的本地 scope，
/// 供普通对话投影排除医院会话使用。失败静默（不阻塞会话列表）。
struct HydrateHospitalConversationScopesUseCase {
    let remoteAPI: any HospitalCareRemoteServing
    let scopeStore: HospitalConversationScopeStore

    /// - Returns: 实际回填的 scope 数量；请求失败返回 0。
    @discardableResult
    func execute(accountID: Int64) async -> Int {
        guard let conversations = try? await remoteAPI.listAllConversations(pageSize: 100) else {
            return 0
        }
        var count = 0
        for item in conversations {
            guard let memberID = item.memberId, let hospital = item.hospital else {
                continue
            }
            scopeStore.remember(
                HospitalConversationScope(
                    threadID: item.threadId,
                    agentID: item.agent.id,
                    memberID: memberID,
                    hospitalID: hospital.id
                ),
                accountID: accountID
            )
            count += 1
        }
        return count
    }
}
