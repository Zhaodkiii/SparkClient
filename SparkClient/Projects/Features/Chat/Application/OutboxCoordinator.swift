import Foundation

/// 用户消息等 outbox 上送的统一入口，便于与 AI 编排解耦、避免重复逻辑散落。
enum OutboxCoordinator {
    static func pushPendingMessages(
        chatSyncSupervisor: ChatSyncSupervisor,
        logger: Logger
    ) async {
        do {
            try await chatSyncSupervisor.pushOutboxOnly()
        } catch {
            logger.warning(
                "Outbox 上送失败（将依赖后台重试）：\(error.localizedDescription)",
                module: .general
            )
        }
    }
}
