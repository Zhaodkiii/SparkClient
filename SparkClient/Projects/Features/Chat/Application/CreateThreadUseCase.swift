import Foundation

struct CreateThreadUseCase: Sendable {
    let repository: any ChatRepository

    func execute(memberID: Int? = nil, title: String) async -> ChatThread {
        await repository.createThread(memberID: memberID, title: title)
    }
}
