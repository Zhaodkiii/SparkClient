import Foundation

struct RetryFailedMessageUseCase: Sendable {
    let repository: any ChatRepository
    let syncEngine: ChatSyncEngine

    func execute(clientMessageID: UUID) async throws {
        await repository.updateMessageDeliveryState(clientMessageID: clientMessageID, state: .pending)
        try await syncEngine.syncNow()
    }
}
