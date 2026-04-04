import Foundation

struct LoadChatThreadUseCase: Sendable {
    let repository: any ChatRepository

    func execute() async -> ChatThreadSnapshot? {
        guard let thread = await repository.loadActiveThread() else { return nil }
        let messages = await repository.loadMessages(threadID: thread.id)
        return ChatThreadSnapshot(thread: thread, messages: messages)
    }
}
