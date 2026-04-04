import Foundation

struct LoadChatMessagesUseCase: Sendable {
    let repository: any ChatRepository

    func execute(threadID: UUID) async -> [ChatMessage] {
        await repository.loadMessages(threadID: threadID)
    }
}
