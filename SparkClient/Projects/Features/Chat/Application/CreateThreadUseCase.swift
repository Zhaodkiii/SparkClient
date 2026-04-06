import Foundation

struct CreateThreadUseCase: Sendable {
    let repository: any ChatRepository

    func execute(patientID: Int? = nil, title: String) async -> ChatThread {
        let thread = await repository.createThread(patientID: patientID, title: title)
        await repository.setActiveThread(id: thread.id)
        return thread
    }
}
