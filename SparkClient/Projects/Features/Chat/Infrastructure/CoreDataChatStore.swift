import CoreData
import Foundation

actor CoreDataChatStore {
    private enum EntityName {
        static let thread = "ChatThreadEntity"
        static let message = "ChatMessageEntity"
        static let cursor = "ChatSyncCursorEntity"
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

    private let coreDataStack: CoreDataStack
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(coreDataStack: CoreDataStack, logger: Logger = ConsoleLogger()) {
        self.coreDataStack = coreDataStack
    }

    func loadActiveThread() async -> ChatThread? {
        try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "isActive == YES"),
                NSPredicate(format: "isSoftDeleted == NO"),
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return try context.fetch(request).first.flatMap(Self.toThread)
        }
    }

    func loadThread(id: UUID) async -> ChatThread? {
        try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            return try context.fetch(request).first.flatMap(Self.toThread)
        }
    }

    func loadThreads() async -> [ChatThread] {
        (try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            request.predicate = NSPredicate(format: "isSoftDeleted == NO")
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return try context.fetch(request).compactMap(Self.toThread)
        }) ?? []
    }

    func createThread(memberID: Int?, title: String) async -> ChatThread {
        let now = Date()
        let thread = ChatThread(
            memberID: memberID,
            title: title,
            scenario: .chat,
            isDeleted: false,
            deletedAt: nil,
            createdAt: now,
            updatedAt: now,
            serverUpdatedAt: nil
        )

        _ = try? await coreDataStack.performBackgroundTask { context in
            let clearRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            clearRequest.predicate = NSPredicate(format: "isActive == YES")
            for object in try context.fetch(clearRequest) {
                object.setValue(false, forKey: "isActive")
            }

            let object = NSEntityDescription.insertNewObject(forEntityName: EntityName.thread, into: context)
            object.setValue(thread.id, forKey: "id")
            object.setValue(thread.memberID.map { Int64($0) }, forKey: "memberID")
            object.setValue(thread.title, forKey: "title")
            object.setValue(thread.scenario.rawValue, forKey: "scenario")
            object.setValue(false, forKey: "isSoftDeleted")
            object.setValue(nil, forKey: "deletedAt")
            object.setValue(thread.createdAt, forKey: "createdAt")
            object.setValue(thread.updatedAt, forKey: "updatedAt")
            object.setValue(thread.serverUpdatedAt, forKey: "serverUpdatedAt")
            object.setValue(true, forKey: "isActive")
        }

        return thread
    }

    func setActiveThread(id: UUID) async {
        _ = try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            for object in try context.fetch(request) {
                let objectID = object.value(forKey: "id") as? UUID
                let isDeleted = object.value(forKey: "isSoftDeleted") as? Bool ?? false
                object.setValue(objectID == id && isDeleted == false, forKey: "isActive")
            }
        }
    }

    /// 默认返回线程最新消息（尾部）以支持懒加载。
    /// - Parameters:
    ///   - limit: 读取条数，nil 表示读取全部。
    ///   - before: 仅返回 createdAt 严格早于该时间戳的消息（用于分页翻页）。
    func loadMessages(threadID: UUID, limit: Int? = nil, before: Date? = nil) async -> [ChatMessage] {
        (try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
            var predicates: [NSPredicate] = [
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
                    Self.toMessage(object: object, decoder: self.decoder)
                }
            // 因为查询使用 createdAt DESC（便于拿最近 N 条），返回给 UI 前再翻转为正序。
            return rows.reversed()
        }) ?? []
    }

    func countMessages(threadID: UUID) async -> Int {
        (try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSNumber>(entityName: EntityName.message)
            request.resultType = .countResultType
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "threadID == %@", threadID as CVarArg),
                NSPredicate(format: "isTombstone == NO"),
            ])
            return try context.count(for: request)
        }) ?? 0
    }

    func appendMessage(
        threadID: UUID,
        role: ChatMessageRole,
        kind: ChatMessageKind,
        content: String,
        attachments: [ChatAttachment],
        reasoningContent: String?,
        reasoningDurationMs: Int64?,
        reasoningExpanded: Bool,
        reasoningVisibility: ChatReasoningVisibility,
        clientMessageID: UUID,
        serverMessageID: String?,
        deliveryState: ChatDeliveryState
    ) async throws -> ChatMessage {
        let message = ChatMessage(
            threadID: threadID,
            role: role,
            kind: kind,
            content: content,
            attachments: attachments,
            reasoningContent: reasoningContent,
            reasoningDurationMs: reasoningDurationMs,
            reasoningExpanded: reasoningExpanded,
            reasoningVisibility: reasoningVisibility,
            clientMessageID: clientMessageID,
            serverMessageID: serverMessageID,
            deliveryState: deliveryState,
            createdAt: Date(),
            serverUpdatedAt: nil,
            isTombstone: false
        )

        try await coreDataStack.performBackgroundTask { context in
            guard let threadObject = try Self.fetchThread(context: context, threadID: threadID) else {
                throw ChatFeatureError.threadNotFound
            }

            let object = NSEntityDescription.insertNewObject(forEntityName: EntityName.message, into: context)
            try Self.fillMessage(
                object: object,
                message: message,
                encoder: self.encoder
            )

            threadObject.setValue(Date(), forKey: "updatedAt")
        }

        return message
    }

    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState) async {
        _ = try? await coreDataStack.performBackgroundTask { context in
            guard let object = try Self.fetchMessage(
                context: context,
                clientMessageID: clientMessageID,
                serverMessageID: nil
            ) else {
                return
            }
            object.setValue(state.rawValue, forKey: "deliveryState")
            if state == .sent || state == .read {
                object.setValue(Date(), forKey: "serverUpdatedAt")
            }
        }
    }

    func upsertRemoteMessages(_ messages: [ChatMessage], in threadID: UUID) async {
        guard messages.isEmpty == false else { return }

        _ = try? await coreDataStack.performBackgroundTask { context in
            if try Self.fetchThread(context: context, threadID: threadID) == nil {
                let threadObject = NSEntityDescription.insertNewObject(forEntityName: EntityName.thread, into: context)
                let now = Date()
                threadObject.setValue(threadID, forKey: "id")
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
                    clientMessageID: message.clientMessageID,
                    serverMessageID: message.serverMessageID
                ) ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.message, into: context)

                if let local = Self.toMessage(object: object, decoder: self.decoder),
                   Self.shouldKeepLocal(local: local, remote: message) {
                    continue
                }

                try Self.fillMessage(object: object, message: message, encoder: self.encoder)
            }

            if let threadObject = try Self.fetchThread(context: context, threadID: threadID) {
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
    }

    func upsertRemoteThreads(_ threads: [ChatThread]) async {
        guard threads.isEmpty == false else { return }

        _ = try? await coreDataStack.performBackgroundTask { context in
            for thread in threads {
                let object = try Self.fetchThread(context: context, threadID: thread.id)
                    ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.thread, into: context)

                object.setValue(thread.id, forKey: "id")
                object.setValue(thread.memberID.map { Int64($0) }, forKey: "memberID")
                object.setValue(thread.title, forKey: "title")
                object.setValue(thread.scenario.rawValue, forKey: "scenario")
                object.setValue(thread.isDeleted, forKey: "isSoftDeleted")
                object.setValue(thread.deletedAt, forKey: "deletedAt")
                object.setValue(thread.createdAt, forKey: "createdAt")
                object.setValue(thread.updatedAt, forKey: "updatedAt")
                object.setValue(thread.serverUpdatedAt, forKey: "serverUpdatedAt")

                if thread.isDeleted {
                    object.setValue(false, forKey: "isActive")
                }
            }
        }
    }

    func loadOutboxMessages(limit: Int) async -> [ChatMessage] {
        (try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
            request.fetchLimit = max(1, limit)
            // 自动同步只处理 pending；failed 仅允许用户触发手动重试后再入队。
            request.predicate = NSPredicate(format: "deliveryState == %@", ChatDeliveryState.pending.rawValue)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(request).compactMap { object in
                Self.toMessage(object: object, decoder: self.decoder)
            }
        }) ?? []
    }

    /// 本地软删除会话，并记录待上送删除事件。
    func softDeleteThread(id: UUID) async {
        _ = try? await coreDataStack.performBackgroundTask { context in
            let now = Date()

            if let thread = try Self.fetchThread(context: context, threadID: id) {
                thread.setValue(true, forKey: "isSoftDeleted")
                thread.setValue(now, forKey: "deletedAt")
                thread.setValue(now, forKey: "updatedAt")
                thread.setValue(false, forKey: "isActive")
            }

            let key = CursorKey.pendingThreadDelete(id)
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.cursor)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", key)
            let marker = try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.cursor, into: context)
            marker.setValue(key, forKey: "key")
            marker.setValue(now.ISO8601Format(), forKey: "value")
            marker.setValue(now, forKey: "updatedAt")
        }
    }

    /// 保留旧接口：新架构默认转为软删除。
    func deleteThread(id: UUID) async {
        await softDeleteThread(id: id)
    }

    func loadPendingThreadDeletionIDs(limit: Int = 50) async -> [UUID] {
        (try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.cursor)
            request.fetchLimit = max(1, limit)
            request.predicate = NSPredicate(format: "key BEGINSWITH %@", CursorKey.pendingThreadDeletePrefix)
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
        _ = try? await coreDataStack.performBackgroundTask { context in
            let keys = ids.map(CursorKey.pendingThreadDelete)
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.cursor)
            request.predicate = NSPredicate(format: "key IN %@", keys)
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

    private func loadSyncCursor(key: String) async -> ChatSyncCursor? {
        try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.cursor)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", key)
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
        _ = try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.cursor)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", key)
            let object = try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.cursor, into: context)
            object.setValue(key, forKey: "key")
            object.setValue(cursor.value, forKey: "value")
            object.setValue(cursor.updatedAt, forKey: "updatedAt")
        }
    }

    private static func fetchThread(context: NSManagedObjectContext, threadID: UUID) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", threadID as CVarArg)
        return try context.fetch(request).first
    }

    private static func fetchMessage(
        context: NSManagedObjectContext,
        clientMessageID: UUID,
        serverMessageID: String?
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
        request.fetchLimit = 1

        if let serverMessageID, serverMessageID.isEmpty == false {
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "clientMessageID == %@", clientMessageID as CVarArg),
                NSPredicate(format: "serverMessageID == %@", serverMessageID),
            ])
        } else {
            request.predicate = NSPredicate(format: "clientMessageID == %@", clientMessageID as CVarArg)
        }

        return try context.fetch(request).first
    }

    private static func fillMessage(object: NSManagedObject, message: ChatMessage, encoder: JSONEncoder) throws {
        object.setValue(message.id, forKey: "id")
        object.setValue(message.threadID, forKey: "threadID")
        object.setValue(message.role.rawValue, forKey: "role")
        object.setValue(message.kind.rawValue, forKey: "kind")
        object.setValue(message.content, forKey: "content")
        object.setValue(message.reasoningContent, forKey: "reasoningContent")
        object.setValue(message.reasoningDurationMs.map { NSNumber(value: $0) }, forKey: "reasoningDurationMs")
        object.setValue(message.reasoningExpanded, forKey: "reasoningExpanded")
        object.setValue(message.reasoningVisibility.rawValue, forKey: "reasoningVisibility")
        object.setValue(message.clientMessageID, forKey: "clientMessageID")
        object.setValue(message.serverMessageID, forKey: "serverMessageID")
        object.setValue(message.deliveryState.rawValue, forKey: "deliveryState")
        object.setValue(message.createdAt, forKey: "createdAt")
        object.setValue(message.serverUpdatedAt, forKey: "serverUpdatedAt")
        object.setValue(message.isTombstone, forKey: "isTombstone")
        object.setValue(try encoder.encode(message.attachments), forKey: "attachmentsData")
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
            isDeleted: object.value(forKey: "isSoftDeleted") as? Bool ?? false,
            deletedAt: object.value(forKey: "deletedAt") as? Date,
            createdAt: createdAt,
            updatedAt: updatedAt,
            serverUpdatedAt: object.value(forKey: "serverUpdatedAt") as? Date
        )
    }

    private static func toMessage(object: NSManagedObject, decoder: JSONDecoder) -> ChatMessage? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let threadID = object.value(forKey: "threadID") as? UUID,
            let roleRaw = object.value(forKey: "role") as? String,
            let role = ChatMessageRole(rawValue: roleRaw),
            let kindRaw = object.value(forKey: "kind") as? String,
            let kind = ChatMessageKind(rawValue: kindRaw),
            let content = object.value(forKey: "content") as? String,
            let clientMessageID = object.value(forKey: "clientMessageID") as? UUID,
            let deliveryRaw = object.value(forKey: "deliveryState") as? String,
            let deliveryState = ChatDeliveryState(rawValue: deliveryRaw),
            let createdAt = object.value(forKey: "createdAt") as? Date
        else {
            return nil
        }

        let attachmentsData = object.value(forKey: "attachmentsData") as? Data
        let attachments = (try? attachmentsData.flatMap { try decoder.decode([ChatAttachment].self, from: $0) }) ?? []

        let reasoningContent = object.value(forKey: "reasoningContent") as? String
        let reasoningDurationMs: Int64? = {
            if let n = object.value(forKey: "reasoningDurationMs") as? NSNumber {
                return n.int64Value
            }
            return nil
        }()
        let reasoningExpanded = object.value(forKey: "reasoningExpanded") as? Bool ?? false
        let visibilityRaw = object.value(forKey: "reasoningVisibility") as? String
        let reasoningVisibility = ChatReasoningVisibility(rawValue: visibilityRaw ?? "") ?? .full

        return ChatMessage(
            id: id,
            threadID: threadID,
            role: role,
            kind: kind,
            content: content,
            attachments: attachments,
            reasoningContent: reasoningContent,
            reasoningDurationMs: reasoningDurationMs,
            reasoningExpanded: reasoningExpanded,
            reasoningVisibility: reasoningVisibility,
            clientMessageID: clientMessageID,
            serverMessageID: object.value(forKey: "serverMessageID") as? String,
            deliveryState: deliveryState,
            createdAt: createdAt,
            serverUpdatedAt: object.value(forKey: "serverUpdatedAt") as? Date,
            isTombstone: object.value(forKey: "isTombstone") as? Bool ?? false
        )
    }

    private static func shouldKeepLocal(local: ChatMessage, remote: ChatMessage) -> Bool {
        switch (local.serverUpdatedAt, remote.serverUpdatedAt) {
        case let (.some(localDate), .some(remoteDate)):
            return localDate > remoteDate
        case (.some, .none):
            return true
        default:
            return false
        }
    }
}
