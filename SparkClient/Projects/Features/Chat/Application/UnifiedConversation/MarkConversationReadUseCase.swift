import Foundation

/// CHAT-000057 D-016/26.6：统一已读确认入口（普通 AI、院内医生智能体与未来线上问诊共用）。
///
/// 规则：
/// - unknown / 未确认会话：拒绝提交已读，直到类型、成员与读取权限确认成功；
/// - 已读边界：只确认进入会话时已加载的消息，新到消息不被误清；
/// - 幂等：重复打开、视图重建、网络重试不产生负数或重复副作用；
/// - 撤权会话：不提交已读。
struct MarkConversationReadUseCase: Sendable {
    /// 已读执行结果。
    enum Outcome: Equatable, Sendable {
        /// 已提交已读；markedCount 为本次实际清零的消息数（0 表示幂等命中）。
        case marked(markedCount: Int)
        /// unknown 确认前拒绝已读。
        case skippedUnconfirmed
        /// 撤权/删除会话不提交已读。
        case skippedRevoked
    }

    let repository: any ChatMessageStoring
    let logger: Logger

    nonisolated init(repository: any ChatMessageStoring, logger: Logger = ConsoleLogger()) {
        self.repository = repository
        self.logger = logger
    }

    /// 提交一次已读确认。
    /// - Parameters:
    ///   - threadID: 目标会话。
    ///   - accountID: 当前账号（用于日志与将来服务端回执链路；本地存储按内核账号隔离）。
    ///   - capability: 由 Projector/详情页权限校验输出的结构化能力；`canMarkRead == false` 时拒绝。
    ///   - readBoundary: 已读边界（通常为进入会话并完成消息加载的时刻）。
    @discardableResult
    func execute(
        threadID: UUID,
        accountID: Int64,
        capability: ConversationCapability,
        readBoundary: Date = Date()
    ) async -> Outcome {
        guard capability != .revoked else { return .skippedRevoked }
        guard capability.canMarkRead else { return .skippedUnconfirmed }

        let marked = await repository.markAssistantMessagesRead(
            threadID: threadID,
            upTo: readBoundary
        )
        if marked > 0 {
            logger.debug(
                "chat.unified.mark_read account=\(accountID) thread=\(threadID.uuidString.prefix(8)) marked=\(marked)",
                module: .general
            )
        }
        return .marked(markedCount: marked)
    }
}
