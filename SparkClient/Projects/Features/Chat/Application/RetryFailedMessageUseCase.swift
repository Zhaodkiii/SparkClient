import Foundation

struct RetryFailedMessageUseCase: Sendable {
    let repository: any ChatRepository
    let chatSyncSupervisor: ChatSyncSupervisor
    let logger: Logger

    init(
        repository: any ChatRepository,
        chatSyncSupervisor: ChatSyncSupervisor,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.chatSyncSupervisor = chatSyncSupervisor
        self.logger = logger
    }

    func execute(clientMessageID: UUID) async throws {
        logger.info("retry 开始，clientMessageID=\(String(clientMessageID.uuidString.prefix(8)))", module: .general)
        do {
            await repository.updateMessageDeliveryState(clientMessageID: clientMessageID, state: .pending)
            try await chatSyncSupervisor.pushOutboxOnly()
            logger.info("retry 完成，clientMessageID=\(String(clientMessageID.uuidString.prefix(8)))", module: .general)
        } catch {
            logger.error("retry 失败：\(error.localizedDescription)", module: .general)
            throw error
        }
    }
}
