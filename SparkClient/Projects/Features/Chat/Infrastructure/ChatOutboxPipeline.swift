import Foundation

/// 出站：线程删除标记 + outbox 上送；与入站解耦，便于单独测试与重试策略演进。
struct ChatOutboxPipeline: Sendable {
    private let repository: any ChatRepository
    private let outboxStore: ChatOutboxStore
    private let remoteAPI: SparkChatRemoteAPI
    private let mergeEngine: ChatMergeEngine
    private let logger: Logger

    nonisolated init(
        repository: any ChatRepository,
        outboxStore: ChatOutboxStore,
        remoteAPI: SparkChatRemoteAPI,
        mergeEngine: ChatMergeEngine,
        logger: Logger
    ) {
        self.repository = repository
        self.outboxStore = outboxStore
        self.remoteAPI = remoteAPI
        self.mergeEngine = mergeEngine
        self.logger = logger
    }

    func pushPendingThreadDeletions() async throws {
        let pending = await repository.loadPendingThreadDeletionIDs(limit: 50)
        guard pending.isEmpty == false else { return }
        logger.info("准备上送线程删除，count=\(pending.count)", module: .general)
        do {
            let deleted = try await remoteAPI.deleteThreads(threadIDs: pending)
            await repository.removePendingThreadDeletionIDs(deleted)
            logger.info("线程删除上送完成，requested=\(pending.count), accepted=\(deleted.count)", module: .general)
        } catch {
            logger.warning("线程删除上送失败，将后台重试：\(error.localizedDescription)", module: .general)
            throw error
        }
    }

    func pushOutbox() async throws {
        let pending = await outboxStore.pending(limit: 50)
        guard pending.isEmpty == false else { return }

        let toolCount = pending.filter { $0.kind == .tool }.count
        let threads = Set(pending.map(\.threadID)).count
        logger.info(
            "准备上送对话，count=\(pending.count), threads=\(threads), toolMessages=\(toolCount)",
            module: .general
        )

        for message in pending {
            await outboxStore.markSending(message)
        }

        do {
            let payload: [ChatRemoteMessageDTO] = pending.map { message in
                ChatRemoteMessageDTO(
                    threadID: message.threadID,
                    role: message.role.rawValue,
                    kind: message.kind.rawValue,
                    content: message.content,
                    attachments: message.attachments,
                    clientMessageID: message.clientMessageID,
                    serverMessageID: message.serverMessageID,
                    deliveryState: message.deliveryState.rawValue,
                    createdAt: message.createdAt,
                    serverUpdatedAt: message.serverUpdatedAt,
                    isTombstone: message.isTombstone,
                    reasoningContent: message.reasoningContent,
                    reasoningDurationMs: message.reasoningDurationMs,
                    reasoningExpanded: message.reasoningExpanded,
                    reasoningVisibility: message.reasoningVisibility.rawValue
                )
            }

            let pushed = try await remoteAPI.push(messages: payload)
            for message in pending {
                await outboxStore.markSent(message)
            }
            logger.info(
                "上送对话完成，requested=\(pending.count), accepted=\(pushed.count)",
                module: .general
            )

            let grouped = Dictionary(grouping: pushed.compactMap(ChatSyncEngineDTOMapper.toDomain), by: { $0.threadID })
            for (threadID, remoteMessages) in grouped {
                let localMessages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
                let localByClient = Self.indexByClientMessageID(localMessages)
                let merged = remoteMessages.map { remote in
                    mergeEngine.resolve(local: localByClient[remote.clientMessageID], remote: remote)
                }
                await repository.upsertRemoteMessages(merged, in: threadID, enqueueAttachmentDownloadJobs: false)
            }
        } catch {
            for message in pending {
                await outboxStore.markFailed(message)
            }
            logger.error(
                "上送对话失败，count=\(pending.count), toolMessages=\(toolCount), error=\(error.localizedDescription)",
                module: .general
            )
            throw error
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
