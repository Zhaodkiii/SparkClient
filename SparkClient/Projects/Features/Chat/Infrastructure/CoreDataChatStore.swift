import CoreData
import Foundation

actor CoreDataChatStore {
    private enum EntityName {
        static let thread = "ChatThreadEntity"
        static let message = "ChatMessageEntity"
        static let messageBlock = "ChatMessageBlockEntity"
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
    private let encoder = JSONEncoder.default
    private let decoder = JSONDecoder.default
    private let logger: Logger

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
                    try? Self.toMessage(
                        object: object,
                        context: context,
                        ownerAccountID: accountID,
                        decoder: self.decoder,
                        logger: self.logger
                    )
                }
            return rows.reversed()
        }) ?? []
    }

    func loadMessages(clientMessageIDs: [UUID]) async -> [ChatMessage] {
        let uniqueIDs = Array(Set(clientMessageIDs))
        guard uniqueIDs.isEmpty == false else { return [] }
        return (try? await kernel.read { context, accountID in
            guard let accountID else { return [] }
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "clientMessageID IN %@", uniqueIDs),
                NSPredicate(format: "isTombstone == NO"),
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(request).compactMap { object in
                try? Self.toMessage(
                    object: object,
                    context: context,
                    ownerAccountID: accountID,
                    decoder: self.decoder,
                    logger: self.logger
                )
            }
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
                context: context,
                ownerAccountID: accountID,
                logger: self.logger
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

    func upsertLocalMessage(_ message: ChatMessage) async throws -> ChatMessage {
        guard await activeAccountID() != nil else {
            throw ChatFeatureError.threadNotFound
        }
        let inserted = try await kernel.writeWithoutNotification { context, accountID in
            guard let threadObject = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: message.threadID) else {
                throw ChatFeatureError.threadNotFound
            }

            let object: NSManagedObject
            let didInsert: Bool
            if let existing = try Self.fetchMessage(
                context: context,
                ownerAccountID: accountID,
                clientMessageID: message.clientMessageID,
                serverMessageID: nil
            ) {
                object = existing
                didInsert = false
            } else {
                object = NSEntityDescription.insertNewObject(forEntityName: EntityName.message, into: context)
                didInsert = true
            }

            try Self.fillMessage(
                object: object,
                message: message,
                context: context,
                ownerAccountID: accountID,
                logger: self.logger
            )
            threadObject.setValue(Date(), forKey: "updatedAt")
            return didInsert
        }
        await kernel.postChangeNotification(
            ChatConversationChangeEvent(
                threadID: message.threadID,
                kind: inserted ? .messagesAppended : .messagesUpdated,
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

    func applyPushMessageAck(
        clientMessageID: UUID,
        serverMessageID: String?,
        serverUpdatedAt: Date
    ) async {
        let change = try? await kernel.writeWithoutNotification { context, accountID in
            guard let object = try Self.fetchMessage(
                context: context,
                ownerAccountID: accountID,
                clientMessageID: clientMessageID,
                serverMessageID: nil
            ) else {
                return nil as UUID?
            }
            if let serverMessageID, serverMessageID.isEmpty == false {
                object.setValue(serverMessageID, forKey: "serverMessageID")
            }
            object.setValue(serverUpdatedAt, forKey: "serverUpdatedAt")
            return object.value(forKey: "threadID") as? UUID
        }
        if let threadID = change {
            await kernel.postChangeNotification(
                ChatConversationChangeEvent(
                    threadID: threadID,
                    kind: .messagesUpdated,
                    affectedClientMessageIDs: [clientMessageID],
                    affectsThreadList: false
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

            let sortedBlocks = Self.sortBlocksByOrderKey(blocks)
            try Self.replaceBlockRows(
                context: context,
                ownerAccountID: accountID,
                clientMessageID: clientMessageID,
                threadID: threadID,
                blocks: sortedBlocks,
                markChangedBlocksPendingForSync: markPendingForSync
            )
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

    /// 插入或更新消息块（ upsert = update + insert ）
    /// 内部会做版本校验：只有新版本（revision更大）才会覆盖旧数据
    /// - Parameters:
    ///   - clientMessageID: 客户端消息唯一 ID
    ///   - block: 要写入的消息块（文本/卡片/健康数据/工具等）
    ///   - markPendingForSync: 是否标记为待同步（true = 需要上传服务器）
    @discardableResult
    func upsertMessageBlock(
        clientMessageID: UUID,
        block: ChatMessageBlock,
        markPendingForSync: Bool
    ) async -> Bool {
        // 执行数据库写入操作，**不立即发送 UI 刷新通知**（批量写完再统一通知）
        let change = try? await kernel.writeWithoutNotification { context, accountID in
            // 1. 根据客户端消息ID查找对应的数据库消息实体
            guard let messageObject = try Self.fetchMessage(
                context: context,
                ownerAccountID: accountID,
                clientMessageID: clientMessageID,
                serverMessageID: nil
            ) else {
                return nil as (threadID: UUID, needSync: Bool, didApply: Bool)?
            }

            // 2. 获取消息所属的会话 ID
            guard let threadID = messageObject.value(forKey: "threadID") as? UUID else {
                return nil as (threadID: UUID, needSync: Bool, didApply: Bool)?
            }

            // 3. 【核心】插入或更新块（仅当新版本 revision 更大时才生效）
            let didApply = try Self.upsertBlockRowIfNewer(
                context: context,
                ownerAccountID: accountID,
                clientMessageID: clientMessageID,
                threadID: threadID,
                block: block,
                markPendingForSync: markPendingForSync
            )

            // 如果块未生效（版本过旧被丢弃），直接返回，不更新状态
            guard didApply else {
                return (threadID: threadID, needSync: false, didApply: false)
            }

            // 4. 更新消息的【服务器更新时间】
            messageObject.setValue(Date(), forKey: "serverUpdatedAt")

            // 5. 同步更新会话的最后更新时间（用于会话列表排序）
            if let thread = try Self.fetchThread(context: context, ownerAccountID: accountID, threadID: threadID) {
                thread.setValue(Date(), forKey: "updatedAt")
            }

            // 返回：会话ID + 是否需要同步
            return (threadID: threadID, needSync: markPendingForSync, didApply: true)
        }

        // MARK: 写入完成 → 发送 UI 刷新通知
        if let change {
            await kernel.postChangeNotification(
                ChatConversationChangeEvent(
                    threadID: change.threadID,
                    kind: .messagesUpdated,        // 事件类型：消息已更新
                    affectedClientMessageIDs: [clientMessageID], // 受影响的消息 ID
                    affectsThreadList: change.needSync || change.didApply // 块内容变更也刷新对话页
                )
            )
        }
        return change?.didApply ?? false
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

                let local = try? Self.toMessage(
                    object: object,
                    context: context,
                    ownerAccountID: accountID,
                    decoder: self.decoder,
                    logger: self.logger
                )
                if let local,
                   mergeEngine.shouldSkipApplyingRemote(local: local, remote: message) {
                    continue
                }

                let messageToApply: ChatMessage
                if let local {
                    let mergedBlocks = Self.mergeBlocksPreservingLocalHealthResources(
                        local: local.blocks,
                        remote: message.blocks
                    )
                    messageToApply = ChatMessage(
                        id: message.id,
                        threadID: message.threadID,
                        role: message.role,
                        blocks: mergedBlocks,
                        clientMessageID: message.clientMessageID,
                        serverMessageID: message.serverMessageID,
                        deliveryState: message.deliveryState,
                        createdAt: message.createdAt,
                        serverUpdatedAt: message.serverUpdatedAt,
                        isTombstone: message.isTombstone,
                        modelName: message.modelName
                    )
                } else {
                    messageToApply = message
                }

                try Self.fillMessage(
                    object: object,
                    message: messageToApply,
                    context: context,
                    ownerAccountID: accountID,
                    logger: self.logger
                )

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
                try? Self.toMessage(
                    object: object,
                    context: context,
                    ownerAccountID: accountID,
                    decoder: self.decoder,
                    logger: self.logger
                )
            }
        }) ?? []
    }

    func loadPendingMessageBlocks(limit: Int) async -> [ChatPendingMessageBlock] {
        (try? await kernel.read { context, accountID in
            guard let accountID else { return [] }
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.messageBlock)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "isPendingSync == YES"),
            ])
            request.sortDescriptors = [
                NSSortDescriptor(key: "updatedAt", ascending: true),
                NSSortDescriptor(key: "id", ascending: true),
            ]
            var pendingBlocks: [ChatPendingMessageBlock] = []
            for row in try context.fetch(request) {
                guard pendingBlocks.count < max(1, limit) else { break }
                guard let threadID = row.value(forKey: "threadID") as? UUID,
                      let clientMessageID = row.value(forKey: "clientMessageID") as? UUID,
                      let block = ChatMessageBlockCodec.decode(row.value(forKey: "payloadData") as? Data)
                else {
                    continue
                }
                if let message = try? Self.fetchMessage(
                    context: context,
                    ownerAccountID: accountID,
                    clientMessageID: clientMessageID,
                    serverMessageID: nil
                ),
                   let deliveryState = message.value(forKey: "deliveryState") as? String {
                    // block_updates 要求服务端已有父消息；整包重推时父消息可能是 .pending。
                    let canPushBlocks = deliveryState == ChatDeliveryState.sent.rawValue
                        || deliveryState == ChatDeliveryState.pending.rawValue
                    if canPushBlocks == false {
                        continue
                    }
                } else {
                    continue
                }
                pendingBlocks.append(
                    ChatPendingMessageBlock(
                        threadID: threadID,
                        clientMessageID: clientMessageID,
                        block: block
                    )
                )
            }
            return pendingBlocks
        }) ?? []
    }

    func markMessageBlocksSynced(ids: [UUID]) async {
        guard ids.isEmpty == false else { return }
        let uniqueIDs = Array(Set(ids))
        _ = try? await kernel.writeWithoutNotification { context, accountID in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.messageBlock)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.ownerPredicate(accountID),
                NSPredicate(format: "id IN %@", uniqueIDs),
            ])
            for row in try context.fetch(request) {
                row.setValue(false, forKey: "isPendingSync")
            }
        }
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
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        logger: Logger? = nil
    ) throws {
        let sortedBlocks = sortBlocksByOrderKey(message.blocks)
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
        try replaceBlockRows(
            context: context,
            ownerAccountID: ownerAccountID,
            clientMessageID: message.clientMessageID,
            threadID: message.threadID,
            blocks: sortedBlocks
        )
    }

    private static func sortBlocksByOrderKey(_ blocks: [ChatMessageBlock]) -> [ChatMessageBlock] {
        reconcilePresentationBlockOrderKeys(blocks).sorted { lhs, rhs in
            switch (lhs.orderKey, rhs.orderKey) {
            case let (l?, r?) where l != r:
                return l < r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    /// 将 toolPresentation 块（如 structuredHealthCards）排在对应 tool 行之后，修复历史数据与同步后乱序。
    private static func reconcilePresentationBlockOrderKeys(_ blocks: [ChatMessageBlock]) -> [ChatMessageBlock] {
        var toolOrderByCallID: [String: Double] = [:]
        for block in blocks where block.kind == .tool {
            guard let toolCallID = block.toolCallID, let orderKey = block.orderKey else { continue }
            toolOrderByCallID[toolCallID] = orderKey
        }

        return blocks.map { block in
            guard isToolPresentationRichBlock(block) else { return block }
            let anchorToolCallID = block.parentToolCallID ?? block.toolCallID
            guard let anchorToolCallID,
                  let toolOrderKey = toolOrderByCallID[anchorToolCallID] else {
                return block
            }
            let desiredOrderKey = toolOrderKey + 100
            guard block.orderKey != desiredOrderKey else { return block }
            return block.replacingIdentity(id: block.id, orderKey: desiredOrderKey)
        }
    }

    private static func isToolPresentationRichBlock(_ block: ChatMessageBlock) -> Bool {
        guard block.nodeRole == .toolPresentation else { return false }
        switch block.kind {
        case .structuredHealthCards, .sleepVisualization, .workoutVisualization,
             .healthResourceReference, .knowledgeCards, .taskCards, .captureCard, .html,
             .pendingMemberToolCards:
            return true
        default:
            return false
        }
    }

    private static func fetchBlockRow(
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        blockID: UUID
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.messageBlock)
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "id == %@", blockID as CVarArg),
        ])
        return try context.fetch(request).first
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
            NSSortDescriptor(key: "id", ascending: true),
        ]
        return try context.fetch(request)
    }

    private static func blockRowSnapshot(from row: NSManagedObject) -> ChatMessageBlockRowSnapshot? {
        guard let id = row.value(forKey: "id") as? UUID else { return nil }
        let kindRaw = row.value(forKey: "kind") as? String
        let anchor: ChatBlockAnchor?
        if let anchorData = row.value(forKey: "anchorData") as? Data {
            anchor = try? JSONDecoder.default.decode(ChatBlockAnchor.self, from: anchorData)
        } else {
            anchor = nil
        }
        let nodeRoleRaw = row.value(forKey: "nodeRole") as? String
        return ChatMessageBlockRowSnapshot(
            id: id,
            kind: kindRaw.flatMap(ChatMessageBlockKind.init(rawValue:)),
            payloadData: row.value(forKey: "payloadData") as? Data,
            anchor: anchor,
            status: (row.value(forKey: "status") as? String).flatMap(ChatMessageBlockStatus.init(rawValue:)),
            revision: row.value(forKey: "revision") as? Int64 ?? 1,
            orderKey: row.value(forKey: "orderKey") as? Double,
            toolCallID: row.value(forKey: "toolCallID") as? String,
            parentToolCallID: row.value(forKey: "parentToolCallID") as? String,
            parentBlockID: row.value(forKey: "parentBlockID") as? UUID,
            nodeRole: nodeRoleRaw.flatMap(ChatMessageBlockNodeRole.init(rawValue:)),
            createdAt: row.value(forKey: "createdAt") as? Date,
            updatedAt: row.value(forKey: "updatedAt") as? Date
        )
    }

    private static func loadBlockRows(
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        clientMessageID: UUID,
        logger: Logger
    ) throws -> [ChatMessageBlock] {
        var blocks: [ChatMessageBlock] = []
        for row in try fetchBlockRows(
            context: context,
            ownerAccountID: ownerAccountID,
            clientMessageID: clientMessageID
        ) {
            guard let snapshot = blockRowSnapshot(from: row) else { continue }
            guard let block = ChatMessageBlockCodec.decodeBlock(from: snapshot) else {
                let kindRaw = snapshot.kind?.rawValue
                if kindRaw == ChatMessageBlockKind.structuredHealthCards.rawValue
                    || kindRaw == ChatMessageBlockKind.healthResourceReference.rawValue {
                    let reason = ChatMessageBlockCodec.decodeFailureReason(
                        payloadData: snapshot.payloadData,
                        kind: snapshot.kind
                    ) ?? "unknown"
                    logger.warning(
                        "messageBlock payload 解码失败，kind=\(kindRaw ?? "?"), clientMessageID=\(clientMessageID.uuidString), blockID=\(snapshot.id.uuidString), bytes=\(snapshot.payloadData?.count ?? 0), reason=\(reason)",
                        module: .general
                    )
                }
                continue
            }
            blocks.append(block)
        }
        return sortBlocksByOrderKey(blocks)
    }

    private static func replaceBlockRows(
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        clientMessageID: UUID,
        threadID: UUID,
        blocks: [ChatMessageBlock],
        markChangedBlocksPendingForSync: Bool = false
    ) throws {
        let incomingIDs = Set(blocks.map(\.id))
        let existingRows = try fetchBlockRows(
            context: context,
            ownerAccountID: ownerAccountID,
            clientMessageID: clientMessageID
        )
        let existingBlocksByID = Dictionary(
            uniqueKeysWithValues: existingRows.compactMap { row -> (UUID, ChatMessageBlock)? in
                guard let snapshot = blockRowSnapshot(from: row),
                      let block = ChatMessageBlockCodec.decodeBlock(from: snapshot)
                else {
                    return nil
                }
                return (snapshot.id, block)
            }
        )
        for row in existingRows {
            guard let id = row.value(forKey: "id") as? UUID else { continue }
            if incomingIDs.contains(id) {
                continue
            }
            let isPendingSync = row.value(forKey: "isPendingSync") as? Bool ?? false
            if isPendingSync || Self.shouldPreserveLocalBlockOnRemoteMerge(existingBlocksByID[id]) {
                continue
            }
            context.delete(row)
        }
        for block in blocks {
            let shouldMarkPending = markChangedBlocksPendingForSync && existingBlocksByID[block.id] != block
            _ = try upsertBlockRowIfNewer(
                context: context,
                ownerAccountID: ownerAccountID,
                clientMessageID: clientMessageID,
                threadID: threadID,
                block: block,
                markPendingForSync: shouldMarkPending
            )
        }
    }

    private static func shouldPreserveLocalBlockOnRemoteMerge(_ block: ChatMessageBlock?) -> Bool {
        guard let block else { return false }
        if block.kind == .healthResourceReference {
            return true
        }
        guard block.nodeRole == .toolPresentation else { return false }
        switch block.kind {
        case .structuredHealthCards, .sleepVisualization, .workoutVisualization,
             .healthResourceReference, .knowledgeCards, .taskCards, .captureCard, .html,
             .pendingMemberToolCards:
            return true
        default:
            return false
        }
    }

    /// 远端消息覆盖本地时，保留本地独有的健康资料引用 block。
    private static func mergeBlocksPreservingLocalHealthResources(
        local: [ChatMessageBlock],
        remote: [ChatMessageBlock]
    ) -> [ChatMessageBlock] {
        let remoteHealthIDs = Set(
            remote
                .filter { $0.kind == .healthResourceReference }
                .map(\.id)
        )
        let preserved = local.filter { block in
            block.kind == .healthResourceReference && remoteHealthIDs.contains(block.id) == false
        }
        guard preserved.isEmpty == false else { return remote }
        return sortBlocksByOrderKey(remote + preserved)
    }

    @discardableResult
    private static func upsertBlockRowIfNewer(
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        clientMessageID: UUID,
        threadID: UUID,
        block: ChatMessageBlock,
        markPendingForSync: Bool = false
    ) throws -> Bool {
        let row = try fetchBlockRow(context: context, ownerAccountID: ownerAccountID, blockID: block.id)
            ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.messageBlock, into: context)
        let localRevision = row.value(forKey: "revision") as? Int64
        let localStatusRaw = row.value(forKey: "status") as? String
        let localStatus = localStatusRaw.flatMap(ChatMessageBlockStatus.init(rawValue:))

        let shouldPromotePendingFromLocal = Self.shouldPromotePendingFromLocal(
            localStatus: localStatus,
            incoming: block
        )
        if let localRevision, localRevision > block.revision, shouldPromotePendingFromLocal == false {
            return false
        }
        if localStatus == .ready, block.status == .pending {
            let allowPendingOverEmptyReady = block.kind == .structuredHealthCards
                && Self.localStructuredHealthCardsHasDisplayableContent(row: row) == false
            if allowPendingOverEmptyReady == false {
                return false
            }
        }
        if let localRevision,
           localRevision == block.revision,
           localStatus == block.status,
           block.status == .pending {
            return false
        }

        row.setValue(block.id, forKey: "id")
        row.setValue(ownerAccountID, forKey: Field.ownerAccountID)
        row.setValue(threadID, forKey: "threadID")
        row.setValue(clientMessageID, forKey: "clientMessageID")
        row.setValue(block.kind.rawValue, forKey: "kind")
        row.setValue(block.status.rawValue, forKey: "status")
        row.setValue(block.revision, forKey: "revision")
        row.setValue(block.orderKey, forKey: "orderKey")
        row.setValue(block.toolCallID, forKey: "toolCallID")
        row.setValue(block.parentToolCallID, forKey: "parentToolCallID")
        row.setValue(block.parentBlockID, forKey: "parentBlockID")
        row.setValue(block.nodeRole.rawValue, forKey: "nodeRole")
        row.setValue(try? JSONEncoder.default.encode(block.anchor), forKey: "anchorData")
        row.setValue(try ChatMessageBlockCodec.encode(block), forKey: "payloadData")
        row.setValue(block.createdAt, forKey: "createdAt")
        row.setValue(block.updatedAt, forKey: "updatedAt")
        if markPendingForSync {
            row.setValue(true, forKey: "isPendingSync")
        }
        return true
    }

    /// 本地 pending 仅在有实质结果（或失败）时被 ready 覆盖；避免空 ready 抢在异步抽取前清掉等待态。
    private static func shouldPromotePendingFromLocal(
        localStatus: ChatMessageBlockStatus?,
        incoming: ChatMessageBlock
    ) -> Bool {
        guard localStatus == .pending else { return false }
        switch incoming.status {
        case .failed:
            return true
        case .ready:
            if incoming.kind == .structuredHealthCards {
                return incoming.structuredHealthCards?.hasDisplayableCards ?? false
            }
            return true
        default:
            return false
        }
    }

    private static func localStructuredHealthCardsHasDisplayableContent(row: NSManagedObject) -> Bool {
        guard let data = row.value(forKey: "payloadData") as? Data,
              let decoded = ChatMessageBlockCodec.decode(data),
              decoded.kind == .structuredHealthCards else {
            return false
        }
        return decoded.structuredHealthCards?.hasDisplayableCards ?? false
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

    private static func toMessage(
        object: NSManagedObject,
        context: NSManagedObjectContext,
        ownerAccountID: Int64,
        decoder: JSONDecoder,
        logger: Logger
    ) throws -> ChatMessage? {
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

        let blockRows = try loadBlockRows(
            context: context,
            ownerAccountID: ownerAccountID,
            clientMessageID: clientMessageID,
            logger: logger
        )
        let blocks = blockRows

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
            try Self.toMessage(
                object: $0,
                context: context,
                ownerAccountID: ownerAccountID,
                decoder: decoder,
                logger: logger
            )
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
