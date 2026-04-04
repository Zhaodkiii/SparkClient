import Foundation

actor InMemoryChatRepository: ChatRepository {
    private var threads: [UUID: ChatThread] = [:]
    private var threadOrder: [UUID] = []
    private var messagesByThread: [UUID: [ChatMessage]] = [:]
    private var activeThreadID: UUID?

    func loadActiveThread() async -> ChatThread? {
        guard let activeThreadID else { return nil }
        return threads[activeThreadID]
    }

    func loadThread(id: UUID) async -> ChatThread? {
        threads[id]
    }

    func createThread(patientID: UUID?, title: String) async -> ChatThread {
        let now = Date()
        let thread = ChatThread(
            id: UUID(),
            patientID: patientID,
            title: title,
            scenario: .chat,
            createdAt: now,
            updatedAt: now
        )
        threads[thread.id] = thread
        threadOrder.insert(thread.id, at: 0)
        messagesByThread[thread.id] = []
        activeThreadID = thread.id
        return thread
    }

    func setActiveThread(id: UUID) async {
        activeThreadID = id
    }

    func loadMessages(threadID: UUID) async -> [ChatMessage] {
        messagesByThread[threadID] ?? []
    }

    func appendMessage(threadID: UUID, role: ChatMessageRole, content: String) async throws -> ChatMessage {
        guard var thread = threads[threadID] else {
            throw ChatFeatureError.threadNotFound
        }

        let message = ChatMessage(
            threadID: threadID,
            role: role,
            content: content
        )

        var history = messagesByThread[threadID] ?? []
        history.append(message)
        messagesByThread[threadID] = history

        thread = ChatThread(
            id: thread.id,
            patientID: thread.patientID,
            title: thread.title,
            scenario: thread.scenario,
            createdAt: thread.createdAt,
            updatedAt: Date()
        )
        threads[threadID] = thread
        if let index = threadOrder.firstIndex(of: threadID) {
            threadOrder.remove(at: index)
            threadOrder.insert(threadID, at: 0)
        }

        return message
    }
}
