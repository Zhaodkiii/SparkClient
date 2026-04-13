import Foundation

struct LoadChatThreadsUseCase: Sendable {
    let repository: any ChatRepository

    func execute() async -> [ChatThreadListItem] {
        let threads = await repository.loadThreads()
        var items: [ChatThreadListItem] = []
        items.reserveCapacity(threads.count)

        for thread in threads {
            let messages = await repository.loadMessages(threadID: thread.id, limit: nil, before: nil)
            let latest = messages.last
            let preview = latest?.content.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(
                ChatThreadListItem(
                    id: thread.id,
                    thread: thread,
                    latestMessagePreview: (preview?.isEmpty == false ? preview! : thread.listDisplayTitle),
                    latestMessageAt: latest?.createdAt ?? thread.updatedAt,
                    unreadCount: messages.filter { $0.role == .assistant && $0.deliveryState != .read }.count
                )
            )
        }

        return items.sorted { $0.latestMessageAt > $1.latestMessageAt }
    }
}
