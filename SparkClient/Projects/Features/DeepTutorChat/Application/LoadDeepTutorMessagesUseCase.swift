import Foundation

struct LoadDeepTutorMessagesUseCase: Sendable {
    let repository: any DeepTutorLocalChatRepository

    func callAsFunction(conversationID: UUID, limit: Int? = nil, before: Date? = nil) async -> [DeepTutorMessage] {
        let messages = await repository.loadMessages(conversationID: conversationID, limit: limit, before: before)
        return messages.map { DeepTutorMessageReducer.applyBlocks(to: $0) }
    }
}

struct LoadDeepTutorConversationsUseCase: Sendable {
    let repository: any DeepTutorLocalChatRepository

    func callAsFunction() async -> [DeepTutorConversationListItem] {
        await repository.loadConversations()
    }
}

struct CreateDeepTutorConversationUseCase: Sendable {
    let repository: any DeepTutorLocalChatRepository

    func callAsFunction(title: String) async throws -> DeepTutorConversation {
        try await repository.createConversation(title: title)
    }
}
