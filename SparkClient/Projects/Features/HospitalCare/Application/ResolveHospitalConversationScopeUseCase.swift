import Foundation

/// CHAT-000054：解析某个 Thread 是否为医院会话。
/// 本地 scope 未命中时回源服务端 conversation context 接口恢复，
/// 避免重装/换机后医院会话被降级为普通会话。
struct ResolveHospitalConversationScopeUseCase {
    let remoteAPI: any HospitalCareRemoteServing
    let scopeStore: HospitalConversationScopeStore

    /// - Returns: 医院会话返回 scope；普通会话返回 nil；请求失败抛错（由调用方决定阻断策略）。
    func execute(threadID: UUID, accountID: Int64) async throws -> HospitalConversationScope? {
        if let cached = scopeStore.scope(for: threadID, accountID: accountID) {
            return cached
        }
        guard let context = try await remoteAPI.fetchConversationContext(threadID: threadID, memberID: nil) else {
            return nil
        }
        guard let memberID = context.memberId else {
            // 医院会话必有绑定成员；缺失时不按医院会话处理。
            return nil
        }
        let scope = HospitalConversationScope(
            threadID: context.threadId,
            agentID: context.agent.id,
            memberID: memberID,
            hospitalID: context.hospital.id,
            consultationID: context.consultation?.consultationId,
            consultNo: context.consultation?.consultNo
        )
        scopeStore.remember(scope, accountID: accountID)
        return scope
    }
}
