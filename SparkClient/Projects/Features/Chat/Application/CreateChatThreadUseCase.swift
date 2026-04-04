import Foundation

struct CreateChatThreadUseCase: Sendable {
    let repository: any ChatRepository

    func execute(patientID: UUID? = nil, title: String) async -> ChatThreadSnapshot {
        let thread = await repository.createThread(patientID: patientID, title: title)
        await repository.setActiveThread(id: thread.id)
        return ChatThreadSnapshot(thread: thread, messages: [])
    }
}
