import CoreData
import Foundation

actor CoreDataChatStore {
    private enum EntityName {
        static let thread = "ChatThreadEntity"
        static let message = "ChatMessageEntity"
        static let cursor = "ChatSyncCursorEntity"
        static let downloadJob = "ChatAttachmentDownloadEntity"
    }

    private enum Field {
        static let ownerAccountID = "ownerAccountID"
    }

    private enum CursorKey {
        static let mainMessageSync = "chat.main"
        static let threadSync = "chat.thread.cursor"
        static let threadMessageSyncPrefix = "chat.thread.message.cursor."
        static let pendingThreadDeletePrefix = "chat.thread.delete."

        static func pendingThreadDelete(_ threadID: UUID) -> String {
            pendingThreadDeletePrefix + threadID.uuidString.lowercased()
        }

        static func threadMessageSync(_ threadID: UUID) -> String {
            threadMessageSyncPrefix + threadID.uuidString.lowercased()
        }
    }

    private let kernel: ChatDatabaseKernel
    private let snapshotStore: SessionSnapshotStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger: Logger

    /// 统一 blocksData 编解码：JSON + LZFSE（失败时自动降级为纯 JSON）。
    private enum ChatBlockCodec {
        static func encode(_ blocks: [ChatMessageBlock]) throws -> Data {
            let json = try JSONEncoder().encode(blocks)
            if let compressed = try? (json as NSData).compressed(using: .lzfse) {
                return compressed as Data
            }
            return json
        }

        static func decode(_ data: Data?) -> [ChatMessageBlock] {
            guard let data else { return [] }
            if let decompressed = try? (data as NSData).decompressed(using: .lzfse),
               let decoded = try? JSONDecoder().decode([ChatMessageBlock].self, from: decompressed as Data) {
                return decoded
            }
            if let decoded = try? JSONDecoder().decode([ChatMessageBlock].self, from: data) {
                return decoded
            }
            return []
        }
    }

    init(
        coreDataStack: CoreDataStack,
        snapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        logger: Logger = ConsoleLogger()
    ) {
        self.snapshotStore = snapshotStore
        self.kernel = ChatDatabaseKernel(coreDataStack: coreDataStack, snapshotStore: snapshotStore, logger: logger)
        self.logger = logger
    }

    func loadActiveThread() async -> ChatThread? {
        try? await kernel.read { context, accountID in
            guard let accountID else { return nil }
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "isActive == YES"),
                NSPredicate(format: "isSoftDeleted == NO"),
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return try context.fetch(request).first.flatMap(Self.toThread)
        }
    }

    func loadThread(id: UUID) async -> ChatThread? {
        try? await kernel.read { context, accountID in
            guard let accountID else { return nil }
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "id == %@", id as CVarArg),
            ])
            return try context.fetch(request).first.flatMap(Self.toThread)
        }
    }

    func loadThreads() async -> [ChatThread] {
        (try? await kernel.read { context, accountID in
            guard let accountID else { return [] }
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "isSoftDeleted == NO"),
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return try context.fetch(request).compactMap(Self.toThread)
        }) ?? []
    }

    func loadThreadListItems() async -> [ChatThreadListItem] {
        (try? await kernel.read { context, accountID in
            guard let accountID else { return [] }
            let threadRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            threadRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "isSoftDeleted == NO"),
            ])
            threadRequest.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            let threadObjects = try context.fetch(threadRequest)

            var items: [ChatThreadListItem] = []
            items.reserveCapacity(threadObjects.count)
            for threadObject in threadObjects {
                guard let thread = Self.toThread(threadObject) else { continue }
                items.append(
                    try Self.makeThreadListProjectionItem(
                        context: context,
                        ownerAccountID: accountID,
                        thread: thread,
                        decoder: self.decoder,
                        logger: self.logger
                    )
                )
            }

            return items.sorted { $0.latestMessageAt > $1.latestMessageAt }
        }) ?? []
    }

    func loadThreadListItem(threadID: UUID) async -> ChatThreadListItem? {
        (try? await kernel.read { context, accountID in
            guard let accountID else { return nil }
            guard let threadObject = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: threadID) else {
                return nil
            }
            guard let thread = Self.toThread(threadObject), thread.isDeleted == false else { return nil }
            return try Self.makeThreadListProjectionItem(
                context: context,
                ownerAccountID: accountID,
                thread: thread,
                decoder: self.decoder,
                logger: self.logger
            )
        }) ?? nil
    }

    func createThread(
        memberID: Int?,
        title: String,
        imageDeliveryModeRaw: String? = nil,
        currentModelName: String? = nil,
        temperature: Double = 0.6,
        topP: Double = 1.0,
        maxTokens: Int = 14096,
        maxMessages: Int = 20,
        rolePrompt: String = ""
    ) async -> ChatThread {
        guard let accountID = await activeAccountID() else {
            return ChatThread(
                memberID: memberID,
                title: title,
                scenario: .chat,
                currentModelName: currentModelName,
                temperature: temperature,
                topP: topP,
                maxTokens: maxTokens,
                maxMessages: maxMessages,
                rolePrompt: rolePrompt,
                imageDeliveryModeRaw: imageDeliveryModeRaw,
                isDeleted: false,
                deletedAt: nil,
                createdAt: Date(),
                updatedAt: Date(),
                serverUpdatedAt: nil
            )
        }
        let now = Date()
        let thread = ChatThread(
            memberID: memberID,
            title: title,
            scenario: .chat,
            currentModelName: currentModelName,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            maxMessages: maxMessages,
            rolePrompt: rolePrompt,
            imageDeliveryModeRaw: imageDeliveryModeRaw,
            isDeleted: false,
            deletedAt: nil,
            createdAt: now,
            updatedAt: now,
            serverUpdatedAt: nil
        )

        _ = try? await kernel.writeWithoutNotification { context, accountID in
            let clearRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            clearRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "isActive == YES"),
            ])
            for object in try context.fetch(clearRequest) {
                object.setValue(false, forKey: "isActive")
            }

            let object = NSEntityDescription.insertNewObject(forEntityName: EntityName.thread, into: context)
            object.setValue(thread.id, forKey: "id")
            object.setValue(accountID, forKey: Field.ownerAccountID)
            object.setValue(thread.memberID.map { Int64($0) }, forKey: "memberID")
            object.setValue(thread.title, forKey: "title")
            object.setValue(thread.scenario.rawValue, forKey: "scenario")
            object.setValue(false, forKey: "isSoftDeleted")
            object.setValue(nil, forKey: "deletedAt")
            object.setValue(thread.createdAt, forKey: "createdAt")
            object.setValue(thread.updatedAt, forKey: "updatedAt")
            object.setValue(thread.serverUpdatedAt, forKey: "serverUpdatedAt")
            object.setValue(thread.imageDeliveryModeRaw, forKey: "imageDeliveryModeRaw")
            object.setValue(thread.currentModelName, forKey: "currentModelName")
            object.setValue(thread.temperature, forKey: "temperature")
            object.setValue(thread.topP, forKey: "topP")
            object.setValue(thread.maxTokens, forKey: "maxTokens")
            object.setValue(thread.maxMessages, forKey: "maxMessages")
            object.setValue(thread.rolePrompt, forKey: "rolePrompt")
            object.setValue(true, forKey: "isActive")
        }
        await kernel.postChangeNotification(
            ChatConversationChangeEvent(
                threadID: thread.id,
                kind: .threadsChanged,
                affectedClientMessageIDs: [],
                affectsThreadList: true
            )
        )

        return thread
    }

    func updateThreadImageDeliveryMode(threadID: UUID, imageDeliveryModeRaw: String?) async {
        _ = try? await kernel.writeWithoutNotification { context, accountID in
            guard let object = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: threadID) else {
                return
            }
            object.setValue(imageDeliveryModeRaw, forKey: "imageDeliveryModeRaw")
            object.setValue(Date(), forKey: "updatedAt")
        }
        await kernel.postChangeNotification(
            ChatConversationChangeEvent(
                threadID: threadID,
                kind: .threadsChanged,
                affectedClientMessageIDs: [],
                affectsThreadList: true
            )
        )
    }

    func updateThreadCurrentModelName(threadID: UUID, currentModelName: String?) async {
        _ = try? await kernel.writeWithoutNotification { context, accountID in
            guard let object = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: threadID) else {
                return
            }
            object.setValue(currentModelName, forKey: "currentModelName")
            object.setValue(Date(), forKey: "updatedAt")
        }
        await kernel.postChangeNotification(
            ChatConversationChangeEvent(
                threadID: threadID,
                kind: .threadsChanged,
                affectedClientMessageIDs: [],
                affectsThreadList: true
            )
        )
    }

    func updateThreadGenerationConfig(
        threadID: UUID,
        currentModelName: String?,
        temperature: Double,
        topP: Double,
        maxTokens: Int,
        maxMessages: Int,
        rolePrompt: String
    ) async {
        _ = try? await kernel.writeWithoutNotification { context, accountID in
            guard let object = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: threadID) else {
                return
            }
            object.setValue(currentModelName, forKey: "currentModelName")
            object.setValue(temperature, forKey: "temperature")
            object.setValue(min(max(topP, 0), 1), forKey: "topP")
            object.setValue(max(maxTokens, 1), forKey: "maxTokens")
            object.setValue(max(maxMessages, 1), forKey: "maxMessages")
            object.setValue(rolePrompt, forKey: "rolePrompt")
            object.setValue(Date(), forKey: "updatedAt")
        }
        await kernel.postChangeNotification(
            ChatConversationChangeEvent(
                threadID: threadID,
                kind: .threadsChanged,
                affectedClientMessageIDs: [],
                affectsThreadList: true
            )
        )
    }

    func setActiveThread(id: UUID) async {
        _ = try? await kernel.writeWithoutNotification { context, accountID in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            request.predicate = Self.ownerPredicate(accountID)
            for object in try context.fetch(request) {
                let objectID = object.value(forKey: "id") as? UUID
                let isDeleted = object.value(forKey: "isSoftDeleted") as? Bool ?? false
                object.setValue(objectID == id && isDeleted == false, forKey: "isActive")
            }
        }
    }

    func updateThreadMemberBinding(threadID: UUID, memberID: Int?) async {
        _ = try? await kernel.writeWithoutNotification { context, accountID in
            guard let object = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: threadID) else {
                return
            }
            object.setValue(memberID.map { Int64($0) }, forKey: "memberID")
            object.setValue(Date(), forKey: "updatedAt")
        }
        await kernel.postChangeNotification(
            ChatConversationChangeEvent(
                threadID: threadID,
                kind: .threadsChanged,
                affectedClientMessageIDs: [],
                affectsThreadList: true
            )
        )
    }

    func loadMessages(threadID: UUID, limit: Int? = nil, before: Date? = nil) async -> [ChatMessage] {
        (try? await kernel.read { context, accountID in
            guard let accountID else { return [] }
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
            var predicates: [NSPredicate] = [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "threadID == %@", threadID as CVarArg),
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
                .compactMap { object in
                    Self.toMessage(object: object, decoder: self.decoder, logger: self.logger)
                }
            return rows.reversed()
        }) ?? []
    }

    func countMessages(threadID: UUID) async -> Int {
        (try? await kernel.read { context, accountID in
            guard let accountID else { return 0 }
            let request = NSFetchRequest<NSNumber>(entityName: EntityName.message)
            request.resultType = .countResultType
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "threadID == %@", threadID as CVarArg),
                NSPredicate(format: "isTombstone == NO"),
            ])
            return try context.count(for: request)
        }) ?? 0
    }

    func latestServerActivity(for threadID: UUID) async -> Date? {
        (try? await kernel.read { context, accountID in
            guard let accountID else { return nil }
            let base = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "threadID == %@", threadID as CVarArg),
                NSPredicate(format: "isTombstone == NO"),
            ])

            func maxDate(keyPath: String, extra: NSPredicate?) throws -> Date? {
                let request = NSFetchRequest<NSDictionary>(entityName: EntityName.message)
                request.resultType = .dictionaryResultType
                let expr = NSExpressionDescription()
                expr.name = "maxValue"
                expr.expression = NSExpression(forFunction: "max:", arguments: [NSExpression(forKeyPath: keyPath)])
                expr.resultType = NSAttributeDescription.AttributeType.date
                expr.expressionResultType = NSAttributeType.dateAttributeType
                request.propertiesToFetch = [expr]
                var predicates: [NSPredicate] = [base]
                if let extra { predicates.append(extra) }
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                guard let row = try context.fetch(request).first else { return nil }
                return row["maxValue"] as? Date
            }

            let maxCreated = try maxDate(keyPath: "createdAt", extra: nil)
            let maxServer = try maxDate(
                keyPath: "serverUpdatedAt",
                extra: NSPredicate(format: "serverUpdatedAt != nil")
            )
            return [maxCreated, maxServer].compactMap { $0 }.max()
        }) ?? nil
    }

    func appendMessage(_ message: ChatMessage) async throws -> ChatMessage {
        guard await activeAccountID() != nil else {
            throw ChatFeatureError.threadNotFound
        }
        try await kernel.writeWithoutNotification { context, accountID in
            guard let threadObject = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: message.threadID) else {
                throw ChatFeatureError.threadNotFound
            }

            let object = NSEntityDescription.insertNewObject(forEntityName: EntityName.message, into: context)
            try Self.fillMessage(
                object: object,
                message: message,
                ownerAccountID: accountID,
                encoder: self.encoder
            )

            threadObject.setValue(Date(), forKey: "updatedAt")
        }
        await kernel.postChangeNotification(
            ChatConversationChangeEvent(
                threadID: message.threadID,
                kind: .messagesAppended,
                affectedClientMessageIDs: [message.clientMessageID],
                affectsThreadList: true
            )
        )

        return message
    }

    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState) async {
        let change = try? await kernel.writeWithoutNotification { context, accountID in
            guard let object = try Self.fetchMessage(
                context: context,
                ownerAccountID: accountID,
                clientMessageID: clientMessageID,
                serverMessageID: nil
            ) else {
                return nil as (UUID, Bool)?
            }
            let roleRaw = object.value(forKey: "role") as? String
            let role = ChatMessageRole(rawValue: roleRaw ?? "") ?? .user
            object.setValue(state.rawValue, forKey: "deliveryState")
            if state == .sent || state == .read {
                object.setValue(Date(), forKey: "serverUpdatedAt")
            }
            guard let threadID = object.value(forKey: "threadID") as? UUID else { return nil }
            // 用户消息送达态变化不改变列表预览/未读角标；助手消息可能改变未读等展示。
            return (threadID, role == .assistant)
        }
        if let change {
            await kernel.postChangeNotification(
                ChatConversationChangeEvent(
                    threadID: change.0,
                    kind: .messagesUpdated,
                    affectedClientMessageIDs: [clientMessageID],
                    affectsThreadList: change.1
                )
            )
        }
    }

    func softDeleteMessage(clientMessageID: UUID) async {
        let change = try? await kernel.writeWithoutNotification { context, accountID in
            guard let object = try Self.fetchMessage(
                context: context,
                ownerAccountID: accountID,
                clientMessageID: clientMessageID,
                serverMessageID: nil
            ) else {
                return nil as UUID?
            }
            object.setValue(true, forKey: "isTombstone")
            object.setValue(Date(), forKey: "serverUpdatedAt")
            return object.value(forKey: "threadID") as? UUID
        }
        if let threadID = change {
            await kernel.postChangeNotification(
                ChatConversationChangeEvent(
                    threadID: threadID,
                    kind: .messagesUpdated,
                    affectedClientMessageIDs: [clientMessageID],
                    affectsThreadList: true
                )
            )
        }
    }

    /// blocks-only 更新入口：直接以完整 blocks 快照覆盖消息内容。
    func updateMessageBlocks(
        clientMessageID: UUID,
        blocks: [ChatMessageBlock],
        markPendingForSync: Bool
    ) async {
        let change = try? await kernel.writeWithoutNotification { context, accountID in
            guard let object = try Self.fetchMessage(
                context: context,
                ownerAccountID: accountID,
                clientMessageID: clientMessageID,
                serverMessageID: nil
            ) else {
                return nil as (UUID, Bool)?
            }
            guard let threadID = object.value(forKey: "threadID") as? UUID else { return nil }
            let latestRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
            latestRequest.fetchLimit = 1
            latestRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "threadID == %@", threadID as CVarArg),
                NSPredicate(format: "isTombstone == NO"),
            ])
            latestRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            let latestClientID = try context.fetch(latestRequest).first?.value(forKey: "clientMessageID") as? UUID
            let thisClientID = object.value(forKey: "clientMessageID") as? UUID
            let isLatestMessage = latestClientID != nil && latestClientID == thisClientID

            object.setValue(try ChatBlockCodec.encode(blocks), forKey: "blocksData")
            if markPendingForSync {
                object.setValue(ChatDeliveryState.pending.rawValue, forKey: "deliveryState")
            }
            object.setValue(Date(), forKey: "serverUpdatedAt")
            if let thread = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: threadID) {
                thread.setValue(Date(), forKey: "updatedAt")
            }
            return (threadID, isLatestMessage)
        }
        if let change {
            await kernel.postChangeNotification(
                ChatConversationChangeEvent(
                    threadID: change.0,
                    kind: .messagesUpdated,
                    affectedClientMessageIDs: [clientMessageID],
                    affectsThreadList: change.1
                )
            )
        }
    }

    func upsertRemoteMessages(
        _ messages: [ChatMessage],
        in threadID: UUID,
        enqueueAttachmentDownloadJobs: Bool = false
    ) async {
        guard messages.isEmpty == false else { return }
        let mergeEngine = ChatMergeEngine()
        _ = try? await kernel.writeWithoutNotification { context, accountID in
            if try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: threadID) == nil {
                let threadObject = NSEntityDescription.insertNewObject(forEntityName: EntityName.thread, into: context)
                let now = Date()
                threadObject.setValue(threadID, forKey: "id")
                threadObject.setValue(accountID, forKey: Field.ownerAccountID)
                threadObject.setValue(nil, forKey: "memberID")
                threadObject.setValue(PromptLocalizer().newThreadTitle(), forKey: "title")
                threadObject.setValue(AIScenario.chat.rawValue, forKey: "scenario")
                threadObject.setValue(false, forKey: "isSoftDeleted")
                threadObject.setValue(nil, forKey: "deletedAt")
                threadObject.setValue(now, forKey: "createdAt")
                threadObject.setValue(now, forKey: "updatedAt")
                threadObject.setValue(now, forKey: "serverUpdatedAt")
                threadObject.setValue(false, forKey: "isActive")
            }

            for message in messages {
                guard message.threadID == threadID else { continue }

                let object = try Self.fetchMessage(
                    context: context,
                    ownerAccountID: accountID,
                    clientMessageID: message.clientMessageID,
                    serverMessageID: message.serverMessageID
                ) ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.message, into: context)

                if let local = Self.toMessage(object: object, decoder: self.decoder, logger: self.logger),
                   mergeEngine.shouldSkipApplyingRemote(local: local, remote: message) {
                    continue
                }

                try Self.fillMessage(object: object, message: message, ownerAccountID: accountID, encoder: self.encoder)

                if enqueueAttachmentDownloadJobs {
                    try Self.insertImageDownloadJobsIfNeeded(
                        context: context,
                        ownerAccountID: accountID,
                        threadID: threadID,
                        message: message,
                        encoder: self.encoder
                    )
                }
            }

            if let threadObject = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: threadID) {
                threadObject.setValue(false, forKey: "isSoftDeleted")
                threadObject.setValue(nil, forKey: "deletedAt")
                threadObject.setValue(Date(), forKey: "updatedAt")
                let latestRemote = messages
                    .compactMap { $0.serverUpdatedAt }
                    .max()
                if let latestRemote {
                    threadObject.setValue(latestRemote, forKey: "serverUpdatedAt")
                }
            }
        }
        await kernel.postChangeNotification(
            ChatConversationChangeEvent(
                threadID: threadID,
                kind: .messagesMerged,
                affectedClientMessageIDs: messages.map(\.clientMessageID),
                affectsThreadList: true
            )
        )
    }

    func upsertRemoteThreads(_ threads: [ChatThread]) async {
        guard threads.isEmpty == false else { return }
        _ = try? await kernel.writeWithoutNotification { context, accountID in
            for thread in threads {
                let object = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: thread.id)
                    ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.thread, into: context)

                object.setValue(thread.id, forKey: "id")
                object.setValue(accountID, forKey: Field.ownerAccountID)
                object.setValue(thread.memberID.map { Int64($0) }, forKey: "memberID")
                object.setValue(thread.title, forKey: "title")
                object.setValue(thread.scenario.rawValue, forKey: "scenario")
                object.setValue(thread.isDeleted, forKey: "isSoftDeleted")
                object.setValue(thread.deletedAt, forKey: "deletedAt")
                object.setValue(thread.createdAt, forKey: "createdAt")
                object.setValue(thread.updatedAt, forKey: "updatedAt")
                object.setValue(thread.serverUpdatedAt, forKey: "serverUpdatedAt")
                object.setValue(thread.imageDeliveryModeRaw, forKey: "imageDeliveryModeRaw")
                object.setValue(thread.currentModelName, forKey: "currentModelName")
                object.setValue(thread.temperature, forKey: "temperature")
                object.setValue(thread.topP, forKey: "topP")
                object.setValue(thread.maxTokens, forKey: "maxTokens")
                object.setValue(thread.maxMessages, forKey: "maxMessages")
                object.setValue(thread.rolePrompt, forKey: "rolePrompt")

                if thread.isDeleted {
                    object.setValue(false, forKey: "isActive")
                }
            }
        }
        await kernel.postChangeNotification(.genericThreadsChanged)
    }

    func loadOutboxMessages(limit: Int) async -> [ChatMessage] {
        (try? await kernel.read { context, accountID in
            guard let accountID else { return [] }
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
            request.fetchLimit = max(1, limit)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "deliveryState == %@", ChatDeliveryState.pending.rawValue),
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(request).compactMap { object in
                Self.toMessage(object: object, decoder: self.decoder, logger: self.logger)
            }
        }) ?? []
    }

    func softDeleteThread(id: UUID) async {
        _ = try? await kernel.writeWithoutNotification { context, accountID in
            let now = Date()

            if let thread = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: id) {
                thread.setValue(true, forKey: "isSoftDeleted")
                thread.setValue(now, forKey: "deletedAt")
                thread.setValue(now, forKey: "updatedAt")
                thread.setValue(false, forKey: "isActive")
            }

            let key = CursorKey.pendingThreadDelete(id)
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.cursor)
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "key == %@", key),
            ])
            let marker = try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.cursor, into: context)
            marker.setValue(accountID, forKey: Field.ownerAccountID)
            marker.setValue(key, forKey: "key")
            marker.setValue(now.ISO8601Format(), forKey: "value")
            marker.setValue(now, forKey: "updatedAt")
        }
        await kernel.postChangeNotification(
            ChatConversationChangeEvent(
                threadID: id,
                kind: .threadsChanged,
                affectedClientMessageIDs: [],
                affectsThreadList: true
            )
        )
    }

    func deleteThread(id: UUID) async {
        await softDeleteThread(id: id)
    }

    func loadPendingThreadDeletionIDs(limit: Int = 50) async -> [UUID] {
        (try? await kernel.read { context, accountID in
            guard let accountID else { return [] }
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.cursor)
            request.fetchLimit = max(1, limit)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "key BEGINSWITH %@", CursorKey.pendingThreadDeletePrefix),
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]
            return try context.fetch(request).compactMap { row in
                guard let key = row.value(forKey: "key") as? String else { return nil }
                let rawID = String(key.dropFirst(CursorKey.pendingThreadDeletePrefix.count))
                return UUID(uuidString: rawID)
            }
        }) ?? []
    }

    func removePendingThreadDeletionIDs(_ ids: [UUID]) async {
        guard ids.isEmpty == false else { return }
        _ = try? await kernel.writeWithoutNotification { context, accountID in
            let keys = ids.map(CursorKey.pendingThreadDelete)
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.cursor)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "key IN %@", keys),
            ])
            for row in try context.fetch(request) {
                context.delete(row)
            }
        }
    }

    func loadSyncCursor() async -> ChatSyncCursor? {
        await loadSyncCursor(key: CursorKey.mainMessageSync)
    }

    func saveSyncCursor(_ cursor: ChatSyncCursor) async {
        await saveSyncCursor(cursor, key: CursorKey.mainMessageSync)
    }

    func loadThreadSyncCursor() async -> ChatSyncCursor? {
        await loadSyncCursor(key: CursorKey.threadSync)
    }

    func saveThreadSyncCursor(_ cursor: ChatSyncCursor) async {
        await saveSyncCursor(cursor, key: CursorKey.threadSync)
    }

    func loadMessageSyncCursor(for threadID: UUID) async -> ChatSyncCursor? {
        await loadSyncCursor(key: CursorKey.threadMessageSync(threadID))
    }

    func saveMessageSyncCursor(_ cursor: ChatSyncCursor, for threadID: UUID) async {
        await saveSyncCursor(cursor, key: CursorKey.threadMessageSync(threadID))
    }

    func loadPendingAttachmentDownloadJobs(limit: Int) async -> [ChatAttachmentDownloadJobRecord] {
        (try? await kernel.read { context, accountID in
            guard let accountID else { return [] }
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.downloadJob)
            request.fetchLimit = max(1, limit)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "stateRaw == %@", ChatAttachmentDownloadJobRecord.State.pending.rawValue),
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]
            return try context.fetch(request).compactMap { Self.toDownloadJob(object: $0, decoder: self.decoder, logger: self.logger) }
        }) ?? []
    }

    func updateAttachmentDownloadJob(id: UUID, state: ChatAttachmentDownloadJobRecord.State, localFileURLString: String?) async {
        _ = try? await kernel.writeWithoutNotification { context, accountID in
            let req = NSFetchRequest<NSManagedObject>(entityName: EntityName.downloadJob)
            req.fetchLimit = 1
            req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "id == %@", id as CVarArg),
            ])
            guard let row = try context.fetch(req).first else { return }
            row.setValue(state.rawValue, forKey: "stateRaw")
            row.setValue(localFileURLString, forKey: "localFileURLString")
            row.setValue(Date(), forKey: "updatedAt")
        }
    }

    private func loadSyncCursor(key: String) async -> ChatSyncCursor? {
        try? await kernel.read { context, accountID in
            guard let accountID else { return nil }
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.cursor)
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "key == %@", key),
            ])
            guard
                let object = try context.fetch(request).first,
                let value = object.value(forKey: "value") as? String,
                let updatedAt = object.value(forKey: "updatedAt") as? Date
            else {
                return nil
            }
            return ChatSyncCursor(value: value, updatedAt: updatedAt)
        }
    }

    private func saveSyncCursor(_ cursor: ChatSyncCursor, key: String) async {
        _ = try? await kernel.writeWithoutNotification { context, accountID in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.cursor)
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "key == %@", key),
            ])
            let object = try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.cursor, into: context)
            object.setValue(accountID, forKey: Field.ownerAccountID)
            object.setValue(key, forKey: "key")
            object.setValue(cursor.value, forKey: "value")
            object.setValue(cursor.updatedAt, forKey: "updatedAt")
        }
    }

    private static func insertImageDownloadJobsIfNeeded(
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        threadID: UUID,
        message: ChatMessage,
        encoder: JSONEncoder
    ) throws {
        let now = Date()
        for attachment in message.blocks
            .filter({ $0.kind == .imageGallery || $0.kind == .fileAttachments })
            .flatMap(\.attachments)
            where attachment.isChatImageLike && attachment.effectiveHTTPSImageDownloadURL != nil {
            let dedupeKey = attachment.imageDownloadDedupeKey
            let existing = NSFetchRequest<NSManagedObject>(entityName: EntityName.downloadJob)
            existing.fetchLimit = 1
            existing.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                ownerPredicate(ownerAccountID),
                NSPredicate(format: "dedupeKey == %@", dedupeKey),
            ])
            if try context.fetch(existing).first != nil {
                continue
            }
            let row = NSEntityDescription.insertNewObject(forEntityName: EntityName.downloadJob, into: context)
            row.setValue(UUID(), forKey: "id")
            row.setValue(ownerAccountID, forKey: Field.ownerAccountID)
            row.setValue(dedupeKey, forKey: "dedupeKey")
            row.setValue(threadID, forKey: "threadID")
            row.setValue(message.clientMessageID, forKey: "clientMessageID")
            row.setValue(attachment.id, forKey: "attachmentID")
            row.setValue(ChatAttachmentDownloadJobRecord.State.pending.rawValue, forKey: "stateRaw")
            row.setValue(try encoder.encode(attachment), forKey: "attachmentPayload")
            row.setValue(nil, forKey: "localFileURLString")
            row.setValue(now, forKey: "createdAt")
            row.setValue(now, forKey: "updatedAt")
        }
    }

    private static func toDownloadJob(
        object: NSManagedObject,
        decoder: JSONDecoder,
        logger: Logger
    ) -> ChatAttachmentDownloadJobRecord? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let dedupeKey = object.value(forKey: "dedupeKey") as? String,
            let threadID = object.value(forKey: "threadID") as? UUID,
            let clientMessageID = object.value(forKey: "clientMessageID") as? UUID,
            let attachmentID = object.value(forKey: "attachmentID") as? UUID,
            let stateRaw = object.value(forKey: "stateRaw") as? String,
            let state = ChatAttachmentDownloadJobRecord.State(rawValue: stateRaw),
            let payload = object.value(forKey: "attachmentPayload") as? Data,
            let snapshot = try? decoder.decode(ChatAttachment.self, from: payload)
        else {
            logger.warning("聊天附件下载任务行解析失败", module: .general)
            return nil
        }
        return ChatAttachmentDownloadJobRecord(
            id: id,
            dedupeKey: dedupeKey,
            threadID: threadID,
            clientMessageID: clientMessageID,
            attachmentID: attachmentID,
            attachmentSnapshot: snapshot,
            state: state,
            localFileURLString: object.value(forKey: "localFileURLString") as? String
        )
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
        ])
        return try context.fetch(request).first
    }

    private static func fetchMessage(
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        clientMessageID: UUID,
        serverMessageID: String?
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
        request.fetchLimit = 1

        if let serverMessageID, serverMessageID.isEmpty == false {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                ownerPredicate(ownerAccountID),
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "clientMessageID == %@", clientMessageID as CVarArg),
                    NSPredicate(format: "serverMessageID == %@", serverMessageID),
                ]),
            ])
        } else {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                ownerPredicate(ownerAccountID),
                NSPredicate(format: "clientMessageID == %@", clientMessageID as CVarArg),
            ])
        }

        return try context.fetch(request).first
    }

    private static func fillMessage(
        object: NSManagedObject,
        message: ChatMessage,
        ownerAccountID: Int64,
        encoder: JSONEncoder
    ) throws {
        object.setValue(message.id, forKey: "id")
        object.setValue(ownerAccountID, forKey: Field.ownerAccountID)
        object.setValue(message.threadID, forKey: "threadID")
        object.setValue(message.role.rawValue, forKey: "role")
        object.setValue(message.modelName, forKey: "modelName")
        object.setValue(message.clientMessageID, forKey: "clientMessageID")
        object.setValue(message.serverMessageID, forKey: "serverMessageID")
        object.setValue(message.deliveryState.rawValue, forKey: "deliveryState")
        object.setValue(message.createdAt, forKey: "createdAt")
        object.setValue(message.serverUpdatedAt, forKey: "serverUpdatedAt")
        object.setValue(message.isTombstone, forKey: "isTombstone")
        object.setValue(try ChatBlockCodec.encode(message.blocks), forKey: "blocksData")
    }

    private static func ownerPredicate(_ accountID: Int64) -> NSPredicate {
        NSPredicate(format: "\(Field.ownerAccountID) == %lld", accountID)
    }

    private func activeAccountID() async -> Int64? {
        await snapshotStore.load()?.accountID
    }

    private static func toThread(_ object: NSManagedObject) -> ChatThread? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let title = object.value(forKey: "title") as? String,
            let scenarioRaw = object.value(forKey: "scenario") as? String,
            let scenario = AIScenario(rawValue: scenarioRaw),
            let createdAt = object.value(forKey: "createdAt") as? Date,
            let updatedAt = object.value(forKey: "updatedAt") as? Date
        else {
            return nil
        }

        return ChatThread(
            id: id,
            memberID: (object.value(forKey: "memberID") as? Int64).map(Int.init),
            title: title,
            scenario: scenario,
            currentModelName: object.value(forKey: "currentModelName") as? String,
            temperature: object.value(forKey: "temperature") as? Double ?? 0.6,
            topP: object.value(forKey: "topP") as? Double ?? 1.0,
            maxTokens: object.value(forKey: "maxTokens") as? Int ?? 4096,
            maxMessages: object.value(forKey: "maxMessages") as? Int ?? 20,
            rolePrompt: object.value(forKey: "rolePrompt") as? String ?? "",
            imageDeliveryModeRaw: object.value(forKey: "imageDeliveryModeRaw") as? String,
            isDeleted: object.value(forKey: "isSoftDeleted") as? Bool ?? false,
            deletedAt: object.value(forKey: "deletedAt") as? Date,
            createdAt: createdAt,
            updatedAt: updatedAt,
            serverUpdatedAt: object.value(forKey: "serverUpdatedAt") as? Date
        )
    }

    private static func toMessage(object: NSManagedObject, decoder: JSONDecoder, logger: Logger) -> ChatMessage? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let threadID = object.value(forKey: "threadID") as? UUID,
            let roleRaw = object.value(forKey: "role") as? String,
            let role = ChatMessageRole(rawValue: roleRaw),
            let clientMessageID = object.value(forKey: "clientMessageID") as? UUID,
            let deliveryRaw = object.value(forKey: "deliveryState") as? String,
            let deliveryState = ChatDeliveryState(rawValue: deliveryRaw),
            let createdAt = object.value(forKey: "createdAt") as? Date
        else {
            return nil
        }

        let blocksData = object.value(forKey: "blocksData") as? Data
        let blocks = ChatBlockCodec.decode(blocksData)

        return ChatMessage(
            id: id,
            threadID: threadID,
            role: role,
            blocks: blocks,
            clientMessageID: clientMessageID,
            serverMessageID: object.value(forKey: "serverMessageID") as? String,
            deliveryState: deliveryState,
            createdAt: createdAt,
            serverUpdatedAt: object.value(forKey: "serverUpdatedAt") as? Date,
            isTombstone: object.value(forKey: "isTombstone") as? Bool ?? false,
            modelName: object.value(forKey: "modelName") as? String
        )
    }

    private static func makeThreadListProjectionItem(
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        thread: ChatThread,
        decoder: JSONDecoder,
        logger: Logger
    ) throws -> ChatThreadListItem {
        let threadID = thread.id

        let latestRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
        latestRequest.fetchLimit = 1
        latestRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "threadID == %@", threadID as CVarArg),
            NSPredicate(format: "isTombstone == NO"),
        ])
        latestRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let latestMessage = try context.fetch(latestRequest).first.flatMap {
            Self.toMessage(object: $0, decoder: decoder, logger: logger)
        }

        let unreadRequest = NSFetchRequest<NSNumber>(entityName: EntityName.message)
        unreadRequest.resultType = .countResultType
        unreadRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "threadID == %@", threadID as CVarArg),
            NSPredicate(format: "isTombstone == NO"),
            NSPredicate(format: "role == %@", ChatMessageRole.assistant.rawValue),
            NSPredicate(format: "deliveryState != %@", ChatDeliveryState.read.rawValue),
        ])
        let unreadCount = try context.count(for: unreadRequest)

        let previewRaw = latestMessage?
            .blocks
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackTitle = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = previewRaw.isEmpty == false ? previewRaw : (fallbackTitle.isEmpty ? "新对话" : fallbackTitle)

        return ChatThreadListItem(
            id: thread.id,
            thread: thread,
            latestMessagePreview: preview,
            latestMessageAt: latestMessage?.createdAt ?? thread.updatedAt,
            unreadCount: unreadCount,
            latestListImageAttachment: Self.firstListThumbnailAttachment(from: latestMessage)
        )
    }

    private static func firstListThumbnailAttachment(from message: ChatMessage?) -> ChatAttachment? {
        guard let message else { return nil }
        for attachment in message.blocks
            .filter({ $0.kind == .imageGallery || $0.kind == .fileAttachments })
            .flatMap(\.attachments)
            where attachment.isChatImageLike {
            if attachment.sparkClientOSSFileUUIDAndFileName() != nil {
                return attachment
            }
            if attachment.effectiveHTTPSImageDownloadURL != nil {
                return attachment
            }
        }
        return nil
    }
}
