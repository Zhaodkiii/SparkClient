import Foundation

protocol DeepTutorLocalChatRepository: Sendable {
    func loadConversations() async -> [DeepTutorConversationListItem]
    func loadConversation(id: UUID) async -> DeepTutorConversation?
    func createConversation(title: String) async throws -> DeepTutorConversation
    func updateConversationTitle(
        id: UUID,
        title: String,
        source: DeepTutorConversationTitleSource
    ) async throws -> DeepTutorConversation
    func updateConversationMemberBinding(conversationID: UUID, memberID: Int?) async throws
    func deleteConversation(id: UUID) async throws
    func loadMessages(conversationID: UUID, limit: Int?, before: Date?) async -> [DeepTutorMessage]
    func countMessages(conversationID: UUID) async -> Int
    func upsertMessage(_ message: DeepTutorMessage) async throws -> DeepTutorMessage
    func softDeleteMessage(id: UUID, conversationID: UUID) async throws
}

extension DeepTutorLocalChatStore: DeepTutorLocalChatRepository {}
