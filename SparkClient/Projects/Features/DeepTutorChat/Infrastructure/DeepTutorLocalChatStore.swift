import CoreData
import Foundation

actor DeepTutorLocalChatStore {
    private enum EntityName {
        static let thread = "ChatThreadEntity"
        static let message = "ChatMessageEntity"
        static let messageBlock = "ChatMessageBlockEntity"
    }

    private enum Field {
        static let ownerAccountID = "ownerAccountID"
    }

    private let kernel: ChatDatabaseKernel
    private let snapshotStore: SessionSnapshotStore
    private let logger: Logger

    init(
        coreDataStack: CoreDataStack,
        snapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        logger: Logger = ConsoleLogger()
    ) {
        self.kernel = ChatDatabaseKernel(coreDataStack: coreDataStack, snapshotStore: snapshotStore, logger: logger)
        self.snapshotStore = snapshotStore
        self.logger = logger
    }

    func loadConversations() async -> [DeepTutorConversationListItem] {
        do {
            return try await kernel.read { context, accountID in
                guard let accountID else {
                    self.logger.warning(
                        "DeepTutor 仓储：loadConversations 时未登录，scenario=\(DeepTutorScenarioConstants.scenario)",
                        module: DeepTutorChatLog.module
                    )
                    return []
                }
                let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    Self.ownerPredicate(accountID),
                    NSPredicate(format: "scenario == %@", DeepTutorScenarioConstants.scenario),
                    NSPredicate(format: "isSoftDeleted == NO"),
                ])
                request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
                let threads = try context.fetch(request)
                var items: [DeepTutorConversationListItem] = []
                for threadObject in threads {
                    guard let conversation = Self.toConversation(threadObject) else {
                        let conversationID = (threadObject.value(forKey: "id") as? UUID).map {
                            DeepTutorChatLog.shortID($0)
                        } ?? "unknown"
                        self.logger.warning(
                            "DeepTutor 仓储：loadConversations 跳过损坏会话 conversation=\(conversationID) reason=missing_required_thread_fields",
                            module: DeepTutorChatLog.module
                        )
                        continue
                    }
                    let preview = Self.latestPreview(
                        context: context,
                        ownerAccountID: accountID,
                        conversationID: conversation.id,
                        logger: self.logger
                    )
                    items.append(
                        DeepTutorConversationListItem(
                            id: conversation.id,
                            conversation: conversation,
                            latestPreview: preview.text,
                            latestMessageAt: preview.date == .distantPast ? conversation.updatedAt : preview.date,
                            latestMessageStatus: preview.status
                        )
                    )
                }
                self.logger.debug(
                    "DeepTutor 仓储：loadConversations count=\(items.count), ownerAccountID=\(accountID), scenario=\(DeepTutorScenarioConstants.scenario)",
                    module: DeepTutorChatLog.module
                )
                return items
            }
        } catch {
            Self.logLoadConversationsFailure(error, logger: logger)
            return []
        }
    }

    func loadConversation(id: UUID) async -> DeepTutorConversation? {
        try? await kernel.read { context, accountID in
            guard let accountID else { return nil }
            guard let object = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: id) else {
                return nil
            }
            return Self.toConversation(object)
        }
    }

    func createConversation(title: String) async throws -> DeepTutorConversation {
        guard await activeAccountID() != nil else {
            logger.warning(
                "DeepTutor 仓储：createConversation 时未登录，title=\(title)",
                module: DeepTutorChatLog.module
            )
            throw DeepTutorChatError.notAuthenticated
        }
        let now = Date()
        let conversation = DeepTutorConversation(title: title, createdAt: now, updatedAt: now)
        let accountID = await activeAccountID()
        logger.info(
            "DeepTutor 仓储：createConversation title=\(title), ownerAccountID=\(accountID.map(String.init) ?? "nil"), scenario=\(DeepTutorScenarioConstants.scenario)",
            module: DeepTutorChatLog.module
        )
        try await kernel.writeWithoutNotification { context, accountID in
            let object = NSEntityDescription.insertNewObject(forEntityName: EntityName.thread, into: context)
            object.setValue(conversation.id, forKey: "id")
            object.setValue(accountID, forKey: Field.ownerAccountID)
            object.setValue(conversation.title, forKey: "title")
            object.setValue(DeepTutorScenarioConstants.scenario, forKey: "scenario")
            object.setValue(conversation.createdAt, forKey: "createdAt")
            object.setValue(conversation.updatedAt, forKey: "updatedAt")
            object.setValue(false, forKey: "isSoftDeleted")
            object.setValue(false, forKey: "isActive")
            object.setValue(false, forKey: "isPinned")
            object.setValue(20, forKey: "maxMessages")
            object.setValue(1.0, forKey: "topP")
            object.setValue("", forKey: "rolePrompt")
        }
        await postChange(.genericThreadsChanged)
        return conversation
    }

    func updateConversationTitle(
        id: UUID,
        title: String,
        source: DeepTutorConversationTitleSource
    ) async throws -> DeepTutorConversation {
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedTitle.isEmpty == false else {
            throw DeepTutorChatError.emptyTitle
        }
        let now = Date()
        logger.info(
            "DeepTutor 仓储：updateConversationTitle conversation=\(DeepTutorChatLog.shortID(id)) title=\(resolvedTitle) source=\(source.rawValue)",
            module: DeepTutorChatLog.module
        )
        try await kernel.writeWithoutNotification { context, accountID in
            guard let object = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: id) else {
                throw DeepTutorChatError.conversationNotFound
            }
            object.setValue(String(resolvedTitle.prefix(100)), forKey: "title")
            object.setValue(now, forKey: "updatedAt")
        }
        await postChange(
            DeepTutorConversationChangeEvent(
                conversationID: id,
                kind: .titleUpdated,
                affectedMessageIDs: [],
                affectsConversationList: true
            )
        )
        guard let updated = await loadConversation(id: id) else {
            throw DeepTutorChatError.conversationNotFound
        }
        return updated
    }

    func updateConversationMemberBinding(conversationID: UUID, memberID: Int?) async throws {
        let now = Date()
        logger.info(
            "DeepTutor 仓储：updateConversationMemberBinding conversation=\(DeepTutorChatLog.shortID(conversationID)) memberID=\(memberID.map(String.init) ?? "-")",
            module: DeepTutorChatLog.module
        )
        try await kernel.writeWithoutNotification { context, accountID in
            guard let object = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: conversationID) else {
                throw DeepTutorChatError.conversationNotFound
            }
            object.setValue(memberID.map { Int64($0) }, forKey: "memberID")
            object.setValue(now, forKey: "updatedAt")
        }
        await postChange(
            DeepTutorConversationChangeEvent(
                conversationID: conversationID,
                kind: .messagesUpdated,
                affectedMessageIDs: [],
                affectsConversationList: false
            )
        )
        guard let updated = await loadConversation(id: conversationID) else {
            throw DeepTutorChatError.conversationNotFound
        }
        _ = updated
    }

    func deleteConversation(id: UUID) async throws {
        try await kernel.writeWithoutNotification { context, accountID in
            guard let object = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: id) else {
                throw DeepTutorChatError.conversationNotFound
            }
            object.setValue(true, forKey: "isSoftDeleted")
            object.setValue(Date(), forKey: "deletedAt")
            object.setValue(Date(), forKey: "updatedAt")
        }
        await postChange(.genericThreadsChanged)
    }

    func loadMessages(conversationID: UUID, limit: Int? = nil, before: Date? = nil) async -> [DeepTutorMessage] {
        let start = Date()
        let limitLabel = limit.map(String.init) ?? "all"
        let beforeLabel = before.map { String($0.timeIntervalSince1970) } ?? "-"
        DeepTutorChatLog.messagesLoadStart(
            conversationID: conversationID,
            limit: limitLabel,
            before: beforeLabel
        )
        do {
            var loadSummary = MessageLoadSummary(conversationID: conversationID)
            let readResult: (
                messages: [DeepTutorMessage],
                repairMessages: [DeepTutorMessage],
                droppedBlocks: Int,
                recoveredBlocks: Int
            ) = try await kernel.read { context, accountID in
            guard let accountID else { return ([], [], 0, 0) }
            guard try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: conversationID) != nil else {
                self.logger.warning(
                    "deeptutor.messages.load.thread_missing conversation=\(DeepTutorChatLog.shortID(conversationID)) ownerAccountID=\(accountID) scenario=\(DeepTutorScenarioConstants.scenario)",
                    module: DeepTutorChatLog.module
                )
                return ([], [], 0, 0)
            }
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
            var predicates: [NSPredicate] = [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "threadID == %@", conversationID as CVarArg),
                NSPredicate(format: "isTombstone == NO"),
            ]
            if let before {
                predicates.append(NSPredicate(format: "createdAt < %@", before as NSDate))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            if let limit, limit > 0 {
                request.fetchLimit = limit
            }
            let rows = try context.fetch(request)
            var messages: [DeepTutorMessage] = []
            var repairMessages: [DeepTutorMessage] = []
            var skippedMessages = 0
            var droppedBlocks = 0
            var recoveredBlocks = 0
            for object in rows {
                do {
                    var messageStats = MessageLoadStats()
                    if let message = try Self.toMessage(
                    object: object,
                    context: context,
                        ownerAccountID: accountID,
                        logger: self.logger,
                        stats: &messageStats
                    ) {
                        messages.append(message)
                        droppedBlocks += messageStats.droppedBlocks
                        recoveredBlocks += messageStats.recoveredBlocks
                        if messageStats.repairApplied {
                            repairMessages.append(message)
                        }
                    } else {
                        skippedMessages += 1
                    }
                } catch {
                    skippedMessages += 1
                    let messageID = (object.value(forKey: "clientMessageID") as? UUID)
                        ?? (object.value(forKey: "id") as? UUID)
                    let deliveryRaw = object.value(forKey: "deliveryState") as? String ?? "-"
                    self.logger.error(
                        "deeptutor.messages.load.message_decode_failed conversation=\(DeepTutorChatLog.shortID(conversationID)) message=\(DeepTutorChatLog.shortID(messageID)) role=\((object.value(forKey: "role") as? String) ?? "-") deliveryState=\(deliveryRaw) error=\(DeepTutorMessageCodec.decodeErrorSummary(error))",
                        module: DeepTutorChatLog.module
                    )
                }
            }
            self.logger.debug(
                "deeptutor.messages.load.rows conversation=\(DeepTutorChatLog.shortID(conversationID)) fetchedRows=\(rows.count) decoded=\(messages.count) skippedMessages=\(skippedMessages) ownerAccountID=\(accountID)",
                module: DeepTutorChatLog.module
            )
            return (messages.reversed(), repairMessages, droppedBlocks, recoveredBlocks)
            }
            let messages = readResult.messages
            loadSummary.droppedBlocks = readResult.droppedBlocks
            loadSummary.recoveredBlocks = readResult.recoveredBlocks
            if readResult.repairMessages.isEmpty == false {
                loadSummary.repairCount = readResult.repairMessages.count
                for message in readResult.repairMessages {
                    try await kernel.writeWithoutNotification { context, accountID in
                        guard let threadObject = try Self.fetchThread(
                            context: context,
                            ownerAccountID: accountID,
                            threadID: message.conversationID
                        ) else { return }
                        guard let object = try Self.fetchMessage(
                            context: context,
                            ownerAccountID: accountID,
                            clientMessageID: message.id
                        ) else { return }
                        try Self.fillMessage(object: object, message: message, context: context, ownerAccountID: accountID)
                        threadObject.setValue(Date(), forKey: "updatedAt")
                    }
                }
            }
            let cost = Date().timeIntervalSince(start)
            loadSummary.totalMessages = messages.count
            DeepTutorChatLog.messagesReloadSummary(
                conversationID: conversationID,
                total: loadSummary.totalMessages,
                recovered: loadSummary.recoveredBlocks,
                dropped: loadSummary.droppedBlocks,
                repairNeeded: loadSummary.repairCount,
                durationMs: Int(cost * 1000)
            )
            DeepTutorChatLog.messagesLoadDone(
                conversationID: conversationID,
                count: messages.count,
                limit: limitLabel,
                durationMs: Int(cost * 1000)
            )
            return messages
        } catch {
            let nsError = error as NSError
            logger.error(
                "deeptutor.messages.load.failed conversation=\(DeepTutorChatLog.shortID(conversationID)) domain=\(nsError.domain) code=\(nsError.code) error=\(error.localizedDescription) userInfo=\(nsError.userInfo)",
                module: DeepTutorChatLog.module
            )
            return []
        }
    }

    func countMessages(conversationID: UUID) async -> Int {
        (try? await kernel.read { context, accountID in
            guard let accountID else { return 0 }
            let request = NSFetchRequest<NSNumber>(entityName: EntityName.message)
            request.resultType = .countResultType
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "threadID == %@", conversationID as CVarArg),
                NSPredicate(format: "isTombstone == NO"),
            ])
            return try context.count(for: request)
        }) ?? 0
    }

    func upsertMessage(_ message: DeepTutorMessage) async throws -> DeepTutorMessage {
        guard await activeAccountID() != nil else {
            throw DeepTutorChatError.notAuthenticated
        }
        let inserted = try await kernel.writeWithoutNotification { context, accountID in
            guard let threadObject = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: message.conversationID) else {
                throw DeepTutorChatError.conversationNotFound
            }
            let object: NSManagedObject
            let didInsert: Bool
            if let existing = try Self.fetchMessage(
                context: context,
                ownerAccountID: accountID,
                clientMessageID: message.id
            ) {
                object = existing
                didInsert = false
            } else {
                object = NSEntityDescription.insertNewObject(forEntityName: EntityName.message, into: context)
                didInsert = true
            }
            try Self.fillMessage(object: object, message: message, context: context, ownerAccountID: accountID)
            threadObject.setValue(Date(), forKey: "updatedAt")
            return didInsert
        }
        let validation = DeepTutorMessageCodec.validateMessageBlocks(message.blocks)
        let askUserCount = message.blocks.filter { $0.kind == .askUser }.count
        if validation.ok {
            DeepTutorChatLog.messagePersistRoundtripOK(
                conversationID: message.conversationID,
                messageID: message.id,
                blockCount: message.blocks.count,
                askUserBlockCount: askUserCount
            )
        } else {
            DeepTutorChatLog.messagePersistRoundtripFailed(
                conversationID: message.conversationID,
                messageID: message.id,
                failedKinds: validation.failedKinds
            )
            DeepTutorChatLog.blockLifecycle(
                conversationID: message.conversationID,
                assistantMessageID: message.id,
                blockKind: validation.failedKinds.joined(separator: ","),
                phase: "codec_roundtrip_failed",
                source: "persistence",
                statusAfter: message.status.rawValue,
                reason: "failedKinds=\(validation.failedKinds.joined(separator: ","))"
            )
        }
        DeepTutorChatLog.messagePersistCompleted(
            conversationID: message.conversationID,
            messageID: message.id,
            status: message.status,
            blockCount: message.blocks.count,
            askUserBlockCount: askUserCount,
            contentLength: message.content.count
        )
        await postChange(
            DeepTutorConversationChangeEvent(
                conversationID: message.conversationID,
                kind: inserted ? .messagesAppended : .messagesUpdated,
                affectedMessageIDs: [message.id],
                affectsConversationList: true
            )
        )
        return message
    }

    func softDeleteMessage(id: UUID, conversationID: UUID) async throws {
        try await kernel.writeWithoutNotification { context, accountID in
            guard let object = try Self.fetchMessage(context: context, ownerAccountID: accountID, clientMessageID: id) else {
                throw DeepTutorChatError.messageNotFound
            }
            object.setValue(true, forKey: "isTombstone")
        }
        await postChange(
            DeepTutorConversationChangeEvent(
                conversationID: conversationID,
                kind: .messagesUpdated,
                affectedMessageIDs: [id],
                affectsConversationList: true
            )
        )
    }

    // MARK: - Private helpers

    private func postChange(_ event: DeepTutorConversationChangeEvent) async {
        await MainActor.run {
            NotificationCenter.default.post(name: .deepTutorChatDatabaseDidChange, object: event)
        }
    }

    private func activeAccountID() async -> Int64? {
        await snapshotStore.load()?.accountID
    }

    private static func ownerPredicate(_ accountID: Int64) -> NSPredicate {
        NSPredicate(format: "\(Field.ownerAccountID) == %lld", accountID)
    }

    private static func fetchThread(
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        threadID: UUID
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "id == %@", threadID as CVarArg),
            NSPredicate(format: "scenario == %@", DeepTutorScenarioConstants.scenario),
            NSPredicate(format: "isSoftDeleted == NO"),
        ])
        return try context.fetch(request).first
    }

    private static func fetchMessage(
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        clientMessageID: UUID
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "clientMessageID == %@", clientMessageID as CVarArg),
        ])
        return try context.fetch(request).first
    }

    private static func toConversation(_ object: NSManagedObject) -> DeepTutorConversation? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let title = object.value(forKey: "title") as? String,
            let createdAt = object.value(forKey: "createdAt") as? Date,
            let updatedAt = object.value(forKey: "updatedAt") as? Date
        else {
            return nil
        }
        return DeepTutorConversation(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: object.value(forKey: "isSoftDeleted") as? Bool ?? false,
            currentModelName: object.value(forKey: "currentModelName") as? String,
            temperature: object.value(forKey: "temperature") as? Double,
            topP: object.value(forKey: "topP") as? Double ?? 1.0,
            maxMessages: object.value(forKey: "maxMessages") as? Int ?? 20,
            memberID: (object.value(forKey: "memberID") as? Int64).map(Int.init)
        )
    }

    private static func latestPreview(
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        conversationID: UUID,
        logger: Logger
    ) -> (text: String, date: Date, status: DeepTutorMessageStatus?) {
        do {
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                ownerPredicate(ownerAccountID),
                NSPredicate(format: "threadID == %@", conversationID as CVarArg),
                NSPredicate(format: "isTombstone == NO"),
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            guard let row = try context.fetch(request).first,
                  let createdAt = row.value(forKey: "createdAt") as? Date else {
                return ("", Date.distantPast, nil)
            }
            var previewStats = MessageLoadStats()
            guard let message = try toMessage(
                    object: row,
                    context: context,
                    ownerAccountID: ownerAccountID,
                    logger: logger,
                    stats: &previewStats
                  ) else {
                return ("", Date.distantPast, nil)
            }
            let preview = DeepTutorMarkdownPreserver.plainPreviewText(from: message)
            return (preview.isEmpty ? "…" : preview, createdAt, message.status)
        } catch {
            logger.warning(
                "deeptutor.list.preview.decode_failed conversation=\(DeepTutorChatLog.shortID(conversationID)) error=\(DeepTutorMessageCodec.decodeErrorSummary(error))",
                module: DeepTutorChatLog.module
            )
            return ("", Date.distantPast, nil)
        }
    }

    private static func logLoadConversationsFailure(_ error: Error, logger: Logger) {
        let nsError = error as NSError
        logger.error(
            "DeepTutor 仓储：loadConversations 失败 domain=\(nsError.domain) code=\(nsError.code) error=\(error.localizedDescription) userInfo=\(nsError.userInfo)",
            module: DeepTutorChatLog.module
        )
    }

    private static func fillMessage(
        object: NSManagedObject,
        message: DeepTutorMessage,
        context: NSManagedObjectContext,
        ownerAccountID: Int64
    ) throws {
        object.setValue(message.id, forKey: "id")
        object.setValue(ownerAccountID, forKey: Field.ownerAccountID)
        object.setValue(message.conversationID, forKey: "threadID")
        object.setValue(message.role.rawValue, forKey: "role")
        object.setValue(message.id, forKey: "clientMessageID")
        object.setValue(message.serverID, forKey: "serverMessageID")
        object.setValue(deliveryState(for: message.status).rawValue, forKey: "deliveryState")
        object.setValue(message.createdAt, forKey: "createdAt")
        object.setValue(message.updatedAt, forKey: "serverUpdatedAt")
        object.setValue(message.isDeleted, forKey: "isTombstone")

        var blocks = message.blocks
        if blocks.contains(where: { $0.kind == .envelope }) == false {
            blocks.insert(DeepTutorMessageCodec.makeEnvelopeBlock(for: message, orderKey: 0), at: 0)
        }
        if message.role != .system,
           blocks.contains(where: { $0.kind == .text }) == false,
           message.content.isEmpty == false {
            blocks.append(DeepTutorMessageCodec.makeTextBlock(messageID: message.id, text: message.content, orderKey: 1000))
        }
        try replaceBlockRows(
            context: context,
            ownerAccountID: ownerAccountID,
            clientMessageID: message.id,
            threadID: message.conversationID,
            blocks: blocks.sorted { $0.orderKey < $1.orderKey }
        )
    }

    private static func toMessage(
        object: NSManagedObject,
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        logger: Logger,
        stats: inout MessageLoadStats
    ) throws -> DeepTutorMessage? {
        guard
            let id = object.value(forKey: "clientMessageID") as? UUID,
            let threadID = object.value(forKey: "threadID") as? UUID,
            let roleRaw = object.value(forKey: "role") as? String,
            let role = DeepTutorMessageRole(rawValue: roleRaw),
            let createdAt = object.value(forKey: "createdAt") as? Date
        else {
            return nil
        }
        let deliveryRaw = object.value(forKey: "deliveryState") as? String ?? ChatDeliveryState.pending.rawValue
        let status = messageStatus(from: ChatDeliveryState(rawValue: deliveryRaw) ?? .pending)
        let blockRows = try fetchBlockRows(context: context, ownerAccountID: ownerAccountID, clientMessageID: id)
        let blocks = blockRows.compactMap {
            toBlock(
                from: $0,
                messageID: id,
                threadID: threadID,
                logger: logger,
                stats: &stats
            )
        }
        let envelope = blocks.compactMap { block -> DeepTutorMessageEnvelope? in
            if case .envelope(let payload) = block.payload { return payload }
            return nil
        }.first
        var text = blocks.compactMap { block -> String? in
            if case .text(let value) = block.payload { return value }
            return nil
        }.joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = Self.contentFromEvents(envelope?.events ?? [])
        }
        if blocks.isEmpty {
            logger.warning(
                "deeptutor.messages.load.message_without_decodable_blocks conversation=\(DeepTutorChatLog.shortID(threadID)) message=\(DeepTutorChatLog.shortID(id)) role=\(role.rawValue) blockRows=\(blockRows.count)",
                module: DeepTutorChatLog.module
            )
        } else if blocks.count < blockRows.count {
            logger.warning(
                "deeptutor.messages.load.partial_blocks conversation=\(DeepTutorChatLog.shortID(threadID)) message=\(DeepTutorChatLog.shortID(id)) decodedBlocks=\(blocks.count) blockRows=\(blockRows.count) contentLength=\(text.count) dropped=\(stats.droppedBlocks) recovered=\(stats.recoveredBlocks)",
                module: DeepTutorChatLog.module
            )
        }
        if stats.repairApplied {
            DeepTutorChatLog.messagesLoadRepairNeeded(
                conversationID: threadID,
                messageID: id,
                repairCount: stats.recoveredBlocks
            )
        }
        let structuralKinds = blocks.compactMap { block -> String? in
            switch block.kind {
            case .quiz, .quizParseError, .askUser, .memberSelection, .generatedFile:
                return block.kind.rawValue
            default:
                return nil
            }
        }
        if structuralKinds.isEmpty == false {
            DeepTutorChatLog.blockRehydratedFromDatabase(
                conversationID: threadID,
                assistantMessageID: id,
                blockKinds: structuralKinds.joined(separator: ",")
            )
        }
        let updatedAt = envelope?.updatedAt ?? (object.value(forKey: "serverUpdatedAt") as? Date) ?? createdAt
        return DeepTutorMessage(
            id: id,
            conversationID: threadID,
            role: role,
            content: text,
            capability: envelope?.capability ?? .chat,
            events: envelope?.events ?? [],
            attachments: envelope?.attachments ?? [],
            requestSnapshot: envelope?.requestSnapshot,
            parentMessageID: envelope?.parentMessageID,
            blocks: blocks,
            serverID: envelope?.serverID ?? (object.value(forKey: "serverMessageID") as? String),
            status: envelope?.status ?? status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: object.value(forKey: "isTombstone") as? Bool ?? false
        )
    }

    private static func fetchBlockRows(
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        clientMessageID: UUID
    ) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.messageBlock)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "clientMessageID == %@", clientMessageID as CVarArg),
        ])
        request.sortDescriptors = [
            NSSortDescriptor(key: "orderKey", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]
        return try context.fetch(request)
    }

    private static func toBlock(
        from row: NSManagedObject,
        messageID: UUID,
        threadID: UUID,
        logger: Logger,
        stats: inout MessageLoadStats
    ) -> DeepTutorMessageBlock? {
        guard let id = row.value(forKey: "id") as? UUID else {
            logger.warning(
                "deeptutor.messages.load.block_missing_id conversation=\(DeepTutorChatLog.shortID(threadID)) message=\(DeepTutorChatLog.shortID(messageID))",
                module: DeepTutorChatLog.module
            )
            return nil
        }
        guard let kindRaw = row.value(forKey: "kind") as? String else {
            logger.warning(
                "deeptutor.messages.load.block_missing_kind conversation=\(DeepTutorChatLog.shortID(threadID)) message=\(DeepTutorChatLog.shortID(messageID)) block=\(DeepTutorChatLog.shortID(id))",
                module: DeepTutorChatLog.module
            )
            return nil
        }
        guard let blockKind = DeepTutorMessageCodec.blockKind(for: kindRaw) else {
            logger.warning(
                "deeptutor.messages.load.block_unknown_kind conversation=\(DeepTutorChatLog.shortID(threadID)) message=\(DeepTutorChatLog.shortID(messageID)) block=\(DeepTutorChatLog.shortID(id)) kind=\(kindRaw)",
                module: DeepTutorChatLog.module
            )
            return nil
        }
        guard let payloadData = row.value(forKey: "payloadData") as? Data else {
            logger.warning(
                "deeptutor.messages.load.block_missing_payload conversation=\(DeepTutorChatLog.shortID(threadID)) message=\(DeepTutorChatLog.shortID(messageID)) block=\(DeepTutorChatLog.shortID(id)) kind=\(kindRaw)",
                module: DeepTutorChatLog.module
            )
            return nil
        }
        guard
            let createdAt = row.value(forKey: "createdAt") as? Date,
            let updatedAt = row.value(forKey: "updatedAt") as? Date
        else {
            logger.warning(
                "deeptutor.messages.load.block_missing_dates conversation=\(DeepTutorChatLog.shortID(threadID)) message=\(DeepTutorChatLog.shortID(messageID)) block=\(DeepTutorChatLog.shortID(id)) kind=\(kindRaw)",
                module: DeepTutorChatLog.module
            )
            return nil
        }
        let rowToolCallID = row.value(forKey: "toolCallID") as? String
        let payload: DeepTutorMessageBlockPayload
        if let decoded = DeepTutorMessageCodec.decodeBlockPayload(
            kind: kindRaw,
            data: payloadData,
            blockToolCallID: rowToolCallID,
            messageID: messageID,
            blockID: id
        ) {
            payload = decoded.payload
            if decoded.repairApplied {
                stats.recoveredBlocks += 1
                stats.repairApplied = true
                DeepTutorChatLog.messagesLoadBlockRecovered(
                    conversationID: threadID,
                    messageID: messageID,
                    blockID: id,
                    kind: kindRaw,
                    reason: decoded.repairReason ?? "compat_repair"
                )
            }
        } else {
            stats.droppedBlocks += 1
            DeepTutorChatLog.messagesLoadBlockDropped(
                conversationID: threadID,
                messageID: messageID,
                blockID: id,
                kind: kindRaw,
                payloadBytes: payloadData.count
            )
            logger.error(
                "deeptutor.messages.load.block_decode_failed conversation=\(DeepTutorChatLog.shortID(threadID)) message=\(DeepTutorChatLog.shortID(messageID)) block=\(DeepTutorChatLog.shortID(id)) kind=\(kindRaw) payloadBytes=\(payloadData.count) error=repair_failed",
                module: DeepTutorChatLog.module
            )
            return nil
        }

        var resolvedToolCallID = rowToolCallID
        if case .askUser(let askUser) = payload, resolvedToolCallID?.isEmpty != false {
            resolvedToolCallID = askUser.toolCallID
        }

        return DeepTutorMessageBlock(
            id: id,
            kind: blockKind,
            payload: payload,
            toolCallID: resolvedToolCallID,
            revision: row.value(forKey: "revision") as? Int64 ?? 0,
            orderKey: row.value(forKey: "orderKey") as? Double ?? 0,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func contentFromEvents(_ events: [DeepTutorStreamEvent]) -> String {
        events.compactMap { event -> String? in
            if case let .contentDelta(text, _, _) = event { return text }
            return nil
        }.joined()
    }

    private static func replaceBlockRows(
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        clientMessageID: UUID,
        threadID: UUID,
        blocks: [DeepTutorMessageBlock]
    ) throws {
        let existing = try fetchBlockRows(context: context, ownerAccountID: ownerAccountID, clientMessageID: clientMessageID)
        let existingByID = Dictionary(uniqueKeysWithValues: existing.compactMap { row -> (UUID, NSManagedObject)? in
            guard let id = row.value(forKey: "id") as? UUID else { return nil }
            return (id, row)
        })
        let incomingIDs = Set(blocks.map(\.id))
        for (id, row) in existingByID where incomingIDs.contains(id) == false {
            context.delete(row)
        }
        for block in blocks {
            let row: NSManagedObject
            if let existingRow = existingByID[block.id] {
                let existingRevision = existingRow.value(forKey: "revision") as? Int64 ?? 0
                guard block.revision >= existingRevision else { continue }
                row = existingRow
            } else {
                row = NSEntityDescription.insertNewObject(forEntityName: EntityName.messageBlock, into: context)
            }
            row.setValue(block.id, forKey: "id")
            row.setValue(ownerAccountID, forKey: Field.ownerAccountID)
            row.setValue(clientMessageID, forKey: "clientMessageID")
            row.setValue(threadID, forKey: "threadID")
            row.setValue(DeepTutorMessageCodec.entityKind(for: block.kind), forKey: "kind")
            row.setValue("ready", forKey: "status")
            row.setValue(block.revision, forKey: "revision")
            row.setValue(block.orderKey, forKey: "orderKey")
            row.setValue(block.toolCallID, forKey: "toolCallID")
            row.setValue("timeline", forKey: "nodeRole")
            row.setValue(false, forKey: "isPendingSync")
            row.setValue(block.createdAt, forKey: "createdAt")
            row.setValue(block.updatedAt, forKey: "updatedAt")
            row.setValue(try DeepTutorMessageCodec.encodePayload(block.payload), forKey: "payloadData")
        }
    }

    private static func deliveryState(for status: DeepTutorMessageStatus) -> ChatDeliveryState {
        switch status {
        case .draft, .pending:
            return .pending
        case .streaming:
            return .sending
        case .ready:
            return .sent
        case .failed:
            return .failed
        case .deleted:
            return .failed
        }
    }

    private static func messageStatus(from deliveryState: ChatDeliveryState) -> DeepTutorMessageStatus {
        switch deliveryState {
        case .pending:
            return .pending
        case .sending:
            return .streaming
        case .sent, .read:
            return .ready
        case .failed:
            return .failed
        }
    }
}

private struct MessageLoadStats: Sendable {
    var droppedBlocks = 0
    var recoveredBlocks = 0
    var repairApplied = false
}

private struct MessageLoadSummary: Sendable {
    let conversationID: UUID
    var totalMessages = 0
    var droppedBlocks = 0
    var recoveredBlocks = 0
    var repairCount = 0
}

enum DeepTutorChatError: LocalizedError {
    case notAuthenticated
    case conversationNotFound
    case messageNotFound
    case emptyInput
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .conversationNotFound:
            return "Conversation not found"
        case .messageNotFound:
            return "Message not found"
        case .emptyInput:
            return "Message cannot be empty"
        case .emptyTitle:
            return "Title cannot be empty"
        }
    }
}
