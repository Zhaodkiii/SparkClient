import Foundation

actor ChatSyncEngine {
    private let repository: any ChatRepository
    private let outboxStore: ChatOutboxStore
    private let remoteAPI: SparkChatRemoteAPI
    private let realtimeClient: ChatRealtimeSyncClient?
    private let mergePolicy: ChatMergePolicy
    private let logger: Logger

    init(
        repository: any ChatRepository,
        outboxStore: ChatOutboxStore,
        remoteAPI: SparkChatRemoteAPI,
        realtimeClient: ChatRealtimeSyncClient? = nil,
        mergePolicy: ChatMergePolicy,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.outboxStore = outboxStore
        self.remoteAPI = remoteAPI
        self.realtimeClient = realtimeClient
        self.mergePolicy = mergePolicy
        self.logger = logger
    }

    func syncNow() async throws {
        let start = Date()
        logger.debug("聊天同步开始", category: "chat_sync")
        // 双通道同步：先把本地 outbox 推上去，再按 cursor 拉取增量，避免覆盖未上行数据。
        try await pushOutbox()
        try await pullAndMerge()
        let cost = Date().timeIntervalSince(start)
        logger.info("聊天同步完成，cost=\(format(cost))s", category: "chat_sync")
    }

    func startRealtimeSync() async {
        guard let realtimeClient else { return }
        await realtimeClient.start { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    try await self.syncNow()
                } catch {
                    self.logger.warning("chat realtime sync failed: \(error.localizedDescription)", category: "chat_sync")
                }
            }
        }
    }

    func stopRealtimeSync() async {
        await realtimeClient?.stop()
    }

    private func pushOutbox() async throws {
        let pending = await outboxStore.pending(limit: 50)
        guard pending.isEmpty == false else { return }

        // 上送核心观测字段：消息条数、涉及线程数、工具消息条数（用于判断是否走过工具流转）。
        let toolCount = pending.filter { $0.kind == .tool }.count
        let threads = Set(pending.map(\.threadID)).count
        logger.info(
            "准备上送对话，count=\(pending.count), threads=\(threads), toolMessages=\(toolCount)",
            category: "chat_sync"
        )

        for message in pending {
            await outboxStore.markSending(message)
        }

        do {
            let payload = pending.map { message in
                ChatRemoteMessageDTO(
                    threadID: message.threadID,
                    role: message.role.rawValue,
                    kind: message.kind.rawValue,
                    content: message.content,
                    clientMessageID: message.clientMessageID,
                    serverMessageID: message.serverMessageID,
                    deliveryState: message.deliveryState.rawValue,
                    createdAt: message.createdAt,
                    serverUpdatedAt: message.serverUpdatedAt,
                    isTombstone: message.isTombstone
                )
            }

            let pushed = try await remoteAPI.push(messages: payload)
            for message in pending {
                await outboxStore.markSent(message)
            }
            logger.info(
                "上送对话完成，requested=\(pending.count), accepted=\(pushed.count)",
                category: "chat_sync"
            )

            // 服务端回包是“权威状态”，用 mergePolicy 回写本地，统一修正状态与时间戳。
            let grouped = Dictionary(grouping: pushed.compactMap(Self.toDomain), by: { $0.threadID })
            for (threadID, remoteMessages) in grouped {
                let localMessages = await repository.loadMessages(threadID: threadID)
                let localByClient = Dictionary(uniqueKeysWithValues: localMessages.map { ($0.clientMessageID, $0) })
                let merged = remoteMessages.map { remote in
                    mergePolicy.resolve(local: localByClient[remote.clientMessageID], remote: remote)
                }
                await repository.upsertRemoteMessages(merged, in: threadID)
            }
        } catch {
            for message in pending {
                await outboxStore.markFailed(message)
            }
            logger.error(
                "上送对话失败，count=\(pending.count), toolMessages=\(toolCount), error=\(error.localizedDescription)",
                category: "chat_sync"
            )
            throw error
        }
    }

    private func pullAndMerge() async throws {
        let cursor = await repository.loadSyncCursor()?.value
        logger.debug("拉取对话增量开始，cursor=\(cursor ?? "-")", category: "chat_sync")
        let result = try await remoteAPI.pull(cursor: cursor)

        // 拉取通道只做增量合并，不做 destructive 覆盖，保证本地可逆。
        let grouped = Dictionary(grouping: result.messages.compactMap(Self.toDomain), by: { $0.threadID })
        for (threadID, remoteMessages) in grouped {
            let localMessages = await repository.loadMessages(threadID: threadID)
            let localByClient = Dictionary(uniqueKeysWithValues: localMessages.map { ($0.clientMessageID, $0) })
            let merged = remoteMessages.map { remote in
                mergePolicy.resolve(local: localByClient[remote.clientMessageID], remote: remote)
            }
            await repository.upsertRemoteMessages(merged, in: threadID)
        }

        if let cursor = result.cursor {
            await repository.saveSyncCursor(ChatSyncCursor(value: cursor))
        }
        logger.debug(
            "拉取对话增量完成，messages=\(result.messages.count), threads=\(grouped.count), nextCursor=\(result.cursor ?? "-")",
            category: "chat_sync"
        )
    }

    private static func toDomain(_ remote: ChatRemoteMessageDTO) -> ChatMessage? {
        guard
            let role = ChatMessageRole(rawValue: remote.role),
            let kind = ChatMessageKind(rawValue: remote.kind),
            let deliveryState = ChatDeliveryState(rawValue: remote.deliveryState)
        else {
            return nil
        }

        return ChatMessage(
            threadID: remote.threadID,
            role: role,
            kind: kind,
            content: remote.content,
            attachments: [],
            clientMessageID: remote.clientMessageID,
            serverMessageID: remote.serverMessageID,
            deliveryState: deliveryState,
            createdAt: remote.createdAt,
            serverUpdatedAt: remote.serverUpdatedAt,
            isTombstone: remote.isTombstone
        )
    }

    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }
}
