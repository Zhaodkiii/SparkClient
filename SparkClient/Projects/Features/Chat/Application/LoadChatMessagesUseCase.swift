import Foundation

struct LoadChatMessagesUseCase: Sendable {
    let queryService: ChatQueryService

    func execute(
        threadID: UUID,
        limit: Int? = nil,
        before: Date? = nil
    ) async -> [ChatMessage] {
        await queryService.loadMessages(threadID: threadID, limit: limit, before: before)
    }

    func count(threadID: UUID) async -> Int {
        await queryService.countMessages(threadID: threadID)
    }
}
