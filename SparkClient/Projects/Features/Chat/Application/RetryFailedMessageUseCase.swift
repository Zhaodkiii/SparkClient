import Foundation

struct RetryFailedMessageUseCase: Sendable {
    let repository: any ChatRepository
    let logger: Logger

    init(
        repository: any ChatRepository,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.logger = logger
    }

    func execute(clientMessageID: UUID) async throws {
        logger.info("retry 开始，clientMessageID=\(String(clientMessageID.uuidString.prefix(8)))", module: .general)
        await repository.updateMessageDeliveryState(clientMessageID: clientMessageID, state: .pending)
        logger.info("retry 已标记为待同步，clientMessageID=\(String(clientMessageID.uuidString.prefix(8)))", module: .general)
    }
}
