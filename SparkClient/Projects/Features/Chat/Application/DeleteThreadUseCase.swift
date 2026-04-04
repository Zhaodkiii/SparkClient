import Foundation

struct DeleteThreadUseCase: Sendable {
    let repository: any ChatRepository

    func execute(threadID: UUID) async {
        await repository.deleteThread(id: threadID)
    }
}
