import Foundation

actor ChatSyncEngine {
    private let repository: any ChatRepository
    private let outboxStore: ChatOutboxStore
    private let remoteAPI: SparkChatRemoteAPI
    private let realtimeClient: ChatRealtimeSyncClient?
    private let mergePolicy: ChatMergePolicy
    private let logger: Logger

    private static let syncCursorFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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

    /// 全量同步：上送 outbox + 按全局 cursor 拉取（如下拉刷新）。
    func syncNow() async throws {
        let start = Date()
        logger.debug("聊天同步开始", category: "chat_sync")
        try await pushOutbox()
        let cursor = await repository.loadSyncCursor()?.value
        try await pullAndMerge(cursor: cursor, threadID: nil)
        let cost = Date().timeIntervalSince(start)
        logger.info("聊天同步完成，cost=\(format(cost))s", category: "chat_sync")
    }

    /// 仅上送待同步消息，不拉取（发送成功/重试等路径使用，避免每次增量都打全量 pull）。
    func pushOutboxOnly() async throws {
        logger.debug("聊天仅上送 outbox", category: "chat_sync")
        try await pushOutbox()
    }

    /// 进入具体会话时：先上送，再比对服务端与本地最近一条消息的更新时间，一致则跳过拉取。
    func syncThreadOnOpen(threadID: UUID) async throws {
        let start = Date()
        logger.debug("会话打开同步开始，thread=\(shortID(threadID))", category: "chat_sync")
        try await pushOutbox()

        let localWatermark = await repository.latestServerActivity(for: threadID)

        var serverHead: Date?
        var headFetchFailed = false
        do {
            serverHead = try await remoteAPI.threadHead(threadID: threadID)
        } catch {
            headFetchFailed = true
            logger.warning("thread head 不可用，将尝试按会话拉取：\(error.localizedDescription)", category: "chat_sync")
        }

        if headFetchFailed {
            let cursor = localWatermark.map(Self.formatSyncCursor)
            try await pullAndMerge(cursor: cursor, threadID: threadID)
            let cost = Date().timeIntervalSince(start)
            logger.info("会话打开同步完成（head 降级），cost=\(format(cost))s", category: "chat_sync")
            return
        }

        switch (localWatermark, serverHead) {
        case (nil, nil):
            logger.debug("会话打开同步跳过（本地与服务端均无消息）", category: "chat_sync")
            return
        case let (lw?, sh?):
            if abs(lw.timeIntervalSince(sh)) < 1.0 {
                logger.debug("会话已与服务端对齐，跳过拉取", category: "chat_sync")
                return
            }
        default:
            break
        }

        let cursor = localWatermark.map(Self.formatSyncCursor)
        try await pullAndMerge(cursor: cursor, threadID: threadID)
        let cost = Date().timeIntervalSince(start)
        logger.info("会话打开同步完成，cost=\(format(cost))s", category: "chat_sync")
    }

    func startRealtimeSync() async {
        guard let realtimeClient else { return }
        await realtimeClient.start { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    // 远端增量提示：只上送本地 pending，避免每条 WS 通知都触发全量 pull。
                    try await self.pushOutboxOnly()
                } catch {
                    self.logger.warning("chat realtime push failed: \(error.localizedDescription)", category: "chat_sync")
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
                category: "chat_sync"
            )

            // 服务端回包是“权威状态”，用 mergePolicy 回写本地，统一修正状态与时间戳。
            let grouped = Dictionary(grouping: pushed.compactMap(Self.toDomain), by: { $0.threadID })
            for (threadID, remoteMessages) in grouped {
                let localMessages = await repository.loadMessages(threadID: threadID)
                let localByClient = Self.indexByClientMessageID(localMessages)
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

    private func pullAndMerge(cursor: String?, threadID: UUID?) async throws {
        let scope = threadID.map { "thread=\(shortID($0))" } ?? "global"
        logger.debug("拉取对话增量开始，cursor=\(cursor ?? "-") scope=\(scope)", category: "chat_sync")
        let result = try await remoteAPI.pull(cursor: cursor, threadID: threadID)

        // 拉取通道只做增量合并，不做 destructive 覆盖，保证本地可逆。
        let grouped = Dictionary(grouping: result.messages.compactMap(Self.toDomain), by: { $0.threadID })
        for (threadID, remoteMessages) in grouped {
            let localMessages = await repository.loadMessages(threadID: threadID)
            let localByClient = Self.indexByClientMessageID(localMessages)
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

        let visibility = ChatReasoningVisibility(rawValue: remote.reasoningVisibility ?? "") ?? .full
        return ChatMessage(
            threadID: remote.threadID,
            role: role,
            kind: kind,
            content: remote.content,
            attachments: [],
            reasoningContent: remote.reasoningContent,
            reasoningDurationMs: remote.reasoningDurationMs,
            reasoningExpanded: remote.reasoningExpanded ?? false,
            reasoningVisibility: visibility,
            clientMessageID: remote.clientMessageID,
            serverMessageID: remote.serverMessageID,
            deliveryState: deliveryState,
            createdAt: remote.createdAt,
            serverUpdatedAt: remote.serverUpdatedAt,
            isTombstone: remote.isTombstone
        )
    }

    /// 同一 `clientMessageID` 在 Core Data 中若出现重复行，保留时间更新、更完整的一条，避免 `Dictionary(uniqueKeysWithValues:)` 崩溃。
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

    private static func formatSyncCursor(_ date: Date) -> String {
        syncCursorFormatter.string(from: date)
    }

    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
