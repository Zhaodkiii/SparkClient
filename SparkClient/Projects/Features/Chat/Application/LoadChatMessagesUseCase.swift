import Foundation

struct LoadChatMessagesUseCase: Sendable {
    let repository: any ChatRepository

    func execute(
        threadID: UUID,
        limit: Int? = nil,
        before: Date? = nil
    ) async -> [ChatMessage] {
        await repository.loadMessages(threadID: threadID, limit: limit, before: before)
    }

    func count(threadID: UUID) async -> Int {
        await repository.countMessages(threadID: threadID)
    }
}
