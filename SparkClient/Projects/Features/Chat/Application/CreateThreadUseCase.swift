import Foundation

struct CreateThreadUseCase: Sendable {
    let repository: any ChatRepository
    let aiConfigCenter: AIConfigCenter

    func execute(memberID: Int? = nil, title: String) async -> ChatThread {
        let snapshot = await aiConfigCenter.currentSnapshot()
        return await repository.createThread(
            memberID: memberID,
            title: title,
            imageDeliveryModeRaw: snapshot.defaultThreadImageDeliveryModeRaw
        )
    }
}
