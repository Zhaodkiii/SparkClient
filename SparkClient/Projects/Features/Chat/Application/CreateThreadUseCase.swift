import Foundation

struct CreateThreadUseCase: Sendable {
    let repository: any ChatRepository
    let aiConfigCenter: AIConfigCenter

    func execute(memberID: Int? = nil, title: String) async -> ChatThread {
        let snapshot = await aiConfigCenter.currentSnapshot()
        let defaultSystemPrompt = PromptLocalizer().chatSystemPrompt()
        let thread = await repository.createThread(
            memberID: memberID,
            title: title,
            imageDeliveryModeRaw: snapshot.defaultThreadImageDeliveryModeRaw,
            rolePrompt: defaultSystemPrompt
        )
        return thread
    }
}
