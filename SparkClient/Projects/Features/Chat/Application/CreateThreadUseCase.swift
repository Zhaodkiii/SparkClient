import Foundation

struct CreateThreadUseCase: Sendable {
    let repository: any ChatRepository
    let aiSettingsRepository: any AISettingsRepository

    func execute(memberID: Int? = nil, title: String) async -> ChatThread {
        let snapshot = await aiSettingsRepository.loadSnapshot()
        return await repository.createThread(
            memberID: memberID,
            title: title,
            imageDeliveryModeRaw: snapshot.defaultThreadImageDeliveryModeRaw
        )
    }
}
