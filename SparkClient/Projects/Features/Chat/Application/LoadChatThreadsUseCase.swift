import Foundation

struct LoadChatThreadsUseCase: Sendable {
    let queryService: ChatQueryService

    func execute() async -> [ChatThreadListItem] {
        await queryService.loadThreadListItems()
    }

    func execute(threadID: UUID) async -> ChatThreadListItem? {
        await queryService.loadThreadListItem(threadID: threadID)
    }
}
