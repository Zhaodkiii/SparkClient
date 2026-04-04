import Foundation

struct RetryFailedMessageUseCase: Sendable {
    let repository: any ChatRepository
    let syncEngine: ChatSyncEngine
    let logger: Logger

    init(
        repository: any ChatRepository,
        syncEngine: ChatSyncEngine,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.syncEngine = syncEngine
        self.logger = logger
    }

    func execute(clientMessageID: UUID) async throws {
        logger.info("retry 开始，clientMessageID=\(String(clientMessageID.uuidString.prefix(8)))", category: "chat_flow")
        do {
            await repository.updateMessageDeliveryState(clientMessageID: clientMessageID, state: .pending)
            try await syncEngine.syncNow()
            logger.info("retry 完成，clientMessageID=\(String(clientMessageID.uuidString.prefix(8)))", category: "chat_flow")
        } catch {
            logger.error("retry 失败：\(error.localizedDescription)", category: "chat_flow")
            throw error
        }
    }
}
