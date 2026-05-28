import Foundation

/// 出站：线程删除标记 + outbox 上送；与入站解耦，便于单独测试与重试策略演进。
struct ChatOutboxPipeline: Sendable {
    private let repository: any ChatRepository
    private let outboxStore: ChatOutboxStore
    private let remoteAPI: SparkChatRemoteAPI
    private let logger: Logger

    nonisolated init(
        repository: any ChatRepository,
        outboxStore: ChatOutboxStore,
        remoteAPI: SparkChatRemoteAPI,
        logger: Logger
    ) {
        self.repository = repository
        self.outboxStore = outboxStore
        self.remoteAPI = remoteAPI
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

    func pushThreads() async throws {
        let threads = await repository.loadThreads().filter { $0.isDeleted == false }
        guard threads.isEmpty == false else { return }
        let payload = threads.map(Self.toRemoteThread)
        logger.debug("准备上送会话元数据，count=\(payload.count)", module: .general)
        let accepted = try await remoteAPI.pushThreads(payload)
        let domainThreads = accepted.compactMap(ChatSyncEngineDTOMapper.toDomainThread)
        if domainThreads.isEmpty == false {
            await repository.upsertRemoteThreads(domainThreads)
        }
        logger.debug("会话元数据上送完成，requested=\(payload.count), accepted=\(accepted.count)", module: .general)
    }

    func pushThread(threadID: UUID) async throws {
        guard let thread = await repository.loadThread(id: threadID), thread.isDeleted == false else { return }
        let payload = [Self.toRemoteThread(thread)]
        logger.debug("准备上送会话元数据（单会话），thread=\(shortID(threadID))", module: .general)
        let accepted = try await remoteAPI.pushThreads(payload)
        let domainThreads = accepted.compactMap(ChatSyncEngineDTOMapper.toDomainThread)
        if domainThreads.isEmpty == false {
            await repository.upsertRemoteThreads(domainThreads)
        }
        logger.debug("会话元数据上送完成（单会话），accepted=\(accepted.count)", module: .general)
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    func pushOutbox() async throws {
        let pending = await outboxStore.pending(limit: 50)
        let hasPendingBlocks = await outboxStore.pendingBlocks(limit: 1).isEmpty == false
        guard pending.isEmpty == false || hasPendingBlocks else { return }

        let toolCount = pending.filter { $0.blocks.contains(where: { $0.kind == .tool }) }.count
        let threads = Set(pending.map(\.threadID)).count
        if pending.isEmpty == false {
            logger.info(
                "准备上送对话，count=\(pending.count), threads=\(threads), toolMessages=\(toolCount)",
                module: .general
            )
        }

        for message in pending {
            await outboxStore.markSending(message)
        }

        var messagePushError: Error?

        if pending.isEmpty == false {
            do {
                let pendingIDs = pending.map(\.clientMessageID)
                let messagesToPush = await repository.loadMessages(clientMessageIDs: pendingIDs)
                for message in messagesToPush {
                    let kinds = message.blocks.map { "\($0.kind.rawValue)(\($0.status.rawValue))" }.joined(separator: ", ")
                    logger.info(
                        "push 重载消息 blocks：clientMessageID=\(message.clientMessageID.uuidString), count=\(message.blocks.count), kinds=[\(kinds)]",
                        module: .general
                    )
                }
                let messagesByClientID = Dictionary(uniqueKeysWithValues: messagesToPush.map { ($0.clientMessageID, $0) })
                let threadsByID = Dictionary(uniqueKeysWithValues: await repository.loadThreads().map { ($0.id, $0) })
                let payload: [ChatRemoteMessageDTO] = pending.compactMap { queued in
                    guard let message = messagesByClientID[queued.clientMessageID] else { return nil }
                    return ChatRemoteMessageDTO(
                        threadId: message.threadID,
                        role: message.role.rawValue,
                        blocks: message.blocks,
                        clientMessageId: message.clientMessageID,
                        serverMessageId: message.serverMessageID,
                        deliveryState: message.deliveryState.rawValue,
                        createdAt: message.createdAt,
                        serverUpdatedAt: message.serverUpdatedAt,
                        tombstone: message.isTombstone,
                        threadCurrentModelName: threadsByID[message.threadID]?.currentModelName,
                        threadTemperature: threadsByID[message.threadID]?.temperature,
                        threadTopP: threadsByID[message.threadID]?.topP,
                        threadMaxTokens: threadsByID[message.threadID]?.maxTokens,
                        threadMaxMessages: threadsByID[message.threadID]?.maxMessages,
                        threadRolePrompt: threadsByID[message.threadID]?.rolePrompt,
                        threadSystemPrompt: nil,
                        modelName: message.modelName
                    )
                }

                let ack = try await remoteAPI.push(messages: payload)
                await applyPushAck(
                    ack,
                    pending: messagesToPush,
                    pendingBlocks: []
                )
                for message in messagesToPush {
                    await outboxStore.markSent(
                        message,
                        syncedBlockIDs: message.blocks.map(\.id)
                    )
                }
                let structuredBlockCount = messagesToPush.reduce(0) { partial, message in
                    partial + message.blocks.filter { $0.kind == .structuredHealthCards }.count
                }
                logger.info(
                    "上送对话完成，requested=\(messagesToPush.count), structuredHealthCardBlocks=\(structuredBlockCount), acceptedMessages=\(ack.acceptedMessages.count), acceptedBlockUpdates=\(ack.acceptedBlockUpdates.count)",
                    module: .general
                )
            } catch {
                messagePushError = error
                for message in pending {
                    await outboxStore.markFailed(message)
                }
                logger.error(
                    "上送对话失败，count=\(pending.count), toolMessages=\(toolCount), error=\(error.localizedDescription)",
                    module: .general
                )
            }
        }

        let pendingBlocks = await outboxStore.pendingBlocks(limit: 100)
        if pendingBlocks.isEmpty == false {
            let blockThreads = Set(pendingBlocks.map(\.threadID)).count
            logger.info(
                "准备上送对话块，blocks=\(pendingBlocks.count), threads=\(blockThreads)",
                module: .general
            )
            do {
                let blockPayload = pendingBlocks.map { item in
                    ChatRemoteMessageBlockUpdateDTO(
                        threadId: item.threadID,
                        clientMessageId: item.clientMessageID,
                        block: item.block
                    )
                }
                let ack = try await remoteAPI.pushBlockUpdates(blockPayload)
                await outboxStore.markBlocksSynced(ids: pendingBlocks.map(\.block.id))
                logger.info(
                    "上送对话块完成，requested=\(pendingBlocks.count), acceptedMessages=\(ack.acceptedMessages.count), acceptedBlockUpdates=\(ack.acceptedBlockUpdates.count)",
                    module: .general
                )
                await applyPushAck(
                    ack,
                    pending: [],
                    pendingBlocks: pendingBlocks
                )
            } catch {
                await requeueMessagesForBlockPushFailure(error, pendingBlocks: pendingBlocks)
                logger.error(
                    "上送对话块失败，blocks=\(pendingBlocks.count), error=\(error.localizedDescription)",
                    module: .general
                )
                if messagePushError != nil {
                    throw messagePushError!
                }
                throw error
            }
        }

        if let messagePushError {
            throw messagePushError
        }
    }

    private func requeueMessagesForBlockPushFailure(
        _ error: Error,
        pendingBlocks: [ChatPendingMessageBlock]
    ) async {
        guard let clientMessageID = Self.clientMessageID(fromMessageNotFound: error) else { return }
        let affected = pendingBlocks.filter { $0.clientMessageID == clientMessageID }
        guard affected.isEmpty == false else { return }
        await repository.updateMessageDeliveryState(clientMessageID: clientMessageID, state: .pending)
        logger.warning(
            "block_updates message_not_found，已将消息重新入队整包上送：clientMessageID=\(clientMessageID.uuidString), blocks=\(affected.count)",
            module: .general
        )
    }

    private static func clientMessageID(fromMessageNotFound error: Error) -> UUID? {
        guard case SparkNetworkError.httpError(_, let backend, _) = error,
              backend?.msg == "message_not_found",
              let data = backend?.data,
              case .object(let fields) = data,
              let raw = fields["client_message_id"],
              case .string(let text) = raw,
              let id = UUID(uuidString: text)
        else {
            return nil
        }
        return id
    }

    private func applyPushAck(
        _ ack: ChatPushAckResponse,
        pending: [ChatMessage],
        pendingBlocks: [ChatPendingMessageBlock]
    ) async {
        let messageAckByClientID = Dictionary(
            uniqueKeysWithValues: ack.acceptedMessages.map { ($0.clientMessageId, $0) }
        )

        for message in pending {
            guard let meta = messageAckByClientID[message.clientMessageID] else { continue }
            await repository.applyPushMessageAck(
                clientMessageID: message.clientMessageID,
                serverMessageID: meta.serverMessageId,
                serverUpdatedAt: meta.serverUpdatedAt
            )
        }

        var latestByThread: [UUID: Date] = [:]
        for message in pending {
            guard let meta = messageAckByClientID[message.clientMessageID] else { continue }
            latestByThread[message.threadID] = max(latestByThread[message.threadID] ?? .distantPast, meta.serverUpdatedAt)
        }

        for item in pendingBlocks {
            guard let meta = ack.acceptedBlockUpdates.last(where: { $0.clientMessageId == item.clientMessageID }) else {
                continue
            }
            await repository.applyPushMessageAck(
                clientMessageID: item.clientMessageID,
                serverMessageID: nil,
                serverUpdatedAt: meta.serverUpdatedAt
            )
            latestByThread[item.threadID] = max(latestByThread[item.threadID] ?? .distantPast, meta.serverUpdatedAt)
        }

        for (threadID, date) in latestByThread {
            let exclusiveDate = date.addingTimeInterval(0.001)
            await repository.saveMessageSyncCursor(
                ChatSyncCursor(value: Self.formatSyncCursor(exclusiveDate)),
                for: threadID
            )
        }

    }

    private static let syncCursorFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static func formatSyncCursor(_ date: Date) -> String {
        syncCursorFormatter.string(from: date)
    }

    private static func toRemoteThread(_ thread: ChatThread) -> ChatRemoteThreadDTO {
        ChatRemoteThreadDTO(
            threadID: thread.id,
            title: thread.title,
            scenario: thread.scenario.rawValue,
            patientID: nil,
            memberID: thread.memberID,
            isDeleted: thread.isDeleted,
            deletedAt: thread.deletedAt,
            updatedAt: thread.updatedAt,
            serverUpdatedAt: thread.serverUpdatedAt ?? thread.updatedAt,
            imageDeliveryModeRaw: thread.imageDeliveryModeRaw,
            iconName: thread.iconName,
            iconColorName: thread.iconColorName,
            isPinned: thread.isPinned,
            pinnedAt: thread.pinnedAt,
            currentModelName: thread.currentModelName,
            temperature: thread.temperature,
            topP: thread.topP,
            maxTokens: thread.maxTokens,
            maxMessages: thread.maxMessages,
            rolePrompt: thread.rolePrompt
        )
    }
}
