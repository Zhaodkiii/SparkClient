import Foundation

enum ChatMessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant

    var runtimeRole: AIRuntimeRole {
        switch self {
        case .system:
            return .system
        case .user:
            return .user
        case .assistant:
            return .assistant
        }
    }
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let threadID: UUID
    let role: ChatMessageRole
    let content: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        threadID: UUID,
        role: ChatMessageRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct ChatThreadSnapshot: Sendable {
    let thread: ChatThread
    let messages: [ChatMessage]
}

enum ChatFeatureError: LocalizedError {
    case emptyInput
    case threadNotFound

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请输入消息后再发送。"
        case .threadNotFound:
            return "对话线程不存在，请重新创建。"
        }
    }
}

protocol ChatRepository: Sendable {
    func loadActiveThread() async -> ChatThread?
    func loadThread(id: UUID) async -> ChatThread?
    func createThread(patientID: UUID?, title: String) async -> ChatThread
    func setActiveThread(id: UUID) async
    func loadMessages(threadID: UUID) async -> [ChatMessage]
    func appendMessage(threadID: UUID, role: ChatMessageRole, content: String) async throws -> ChatMessage
}
