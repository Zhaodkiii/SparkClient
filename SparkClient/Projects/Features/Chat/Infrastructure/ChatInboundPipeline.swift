import Foundation

/// 入站合并 + 落库：收口 `pull` 后 DTO→域模型→`upsert` 的路径，并在同一批写入上可选入队附件下载任务。
struct ChatInboundPipeline: Sendable {
    private let repository: any ChatRepository
    private let mergeEngine: ChatMergeEngine

    nonisolated init(repository: any ChatRepository, mergeEngine: ChatMergeEngine) {
        self.repository = repository
        self.mergeEngine = mergeEngine
    }

    /// 将一页远端消息按线程分组后合并写入本地；`enqueueAttachmentDownloadJobs` 为 true 时写入可下载图片任务行。
    func applyRemoteMessages(_ remoteMessages: [ChatMessage], enqueueAttachmentDownloadJobs: Bool) async {
        let grouped = Dictionary(grouping: remoteMessages, by: \.threadID)
        for (threadID, batch) in grouped {
            let localMessages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
            let localByClient = Self.indexByClientMessageID(localMessages)
            let merged = batch.map { remote in
                mergeEngine.resolve(local: localByClient[remote.clientMessageID], remote: remote)
            }
            await repository.upsertRemoteMessages(merged, in: threadID, enqueueAttachmentDownloadJobs: enqueueAttachmentDownloadJobs)
        }
    }

    private static func indexByClientMessageID(_ messages: [ChatMessage]) -> [UUID: ChatMessage] {
        var map: [UUID: ChatMessage] = [:]
        for message in messages {
            if let existing = map[message.clientMessageID] {
                map[message.clientMessageID] = preferMessage(existing, message)
            } else {
                map[message.clientMessageID] = message
            }
        }
        return map
    }

    private static func preferMessage(_ a: ChatMessage, _ b: ChatMessage) -> ChatMessage {
        let da = a.serverUpdatedAt ?? a.createdAt
        let db = b.serverUpdatedAt ?? b.createdAt
        if da != db { return da >= db ? a : b }
        switch (a.serverMessageID, b.serverMessageID) {
        case (nil, .some): return b
        case (.some, nil): return a
        default: return a.id.uuidString >= b.id.uuidString ? a : b
        }
    }
}
