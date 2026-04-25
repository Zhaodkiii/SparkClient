import Foundation

struct CreateThreadUseCase: Sendable {
    let repository: any ChatRepository
    let aiConfigCenter: AIConfigCenter
    let syncChatUseCase: SyncChatUseCase

    func execute(memberID: Int? = nil, title: String) async -> ChatThread {
        let snapshot = await aiConfigCenter.currentSnapshot()
        let thread = await repository.createThread(
            memberID: memberID,
            title: title,
            imageDeliveryModeRaw: snapshot.defaultThreadImageDeliveryModeRaw
        )
        Task {
            try? await syncChatUseCase.pushSingleThread(threadID: thread.id)
        }
        return thread
    }
}
