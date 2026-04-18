import Foundation

/// 读模型 / 查询层：从 ``ChatRepository`` 组装列表等展示模型，供用例与 UI 订阅 DB 变更后刷新。
struct ChatQueryService: Sendable {
    let repository: any ChatRepository

    func loadThreadListItems() async -> [ChatThreadListItem] {
        await repository.loadThreadListItems()
    }

    func loadThreadListItem(threadID: UUID) async -> ChatThreadListItem? {
        await repository.loadThreadListItem(threadID: threadID)
    }

    func loadMessages(threadID: UUID, limit: Int?, before: Date?) async -> [ChatMessage] {
        await repository.loadMessages(threadID: threadID, limit: limit, before: before)
    }

    func countMessages(threadID: UUID) async -> Int {
        await repository.countMessages(threadID: threadID)
    }
}
