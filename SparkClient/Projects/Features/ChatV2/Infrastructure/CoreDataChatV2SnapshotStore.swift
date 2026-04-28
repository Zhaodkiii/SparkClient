import CoreData
import Foundation

/// Chat 2.0 的持久化入口。
///
/// 设计目标：
/// 1. 只保存最终消息快照，不保存展示 patch。
/// 2. V2 使用独立实体名，避免与旧聊天域耦合。
/// 3. 关键日志统一使用中文，便于联调时直接对照业务语义。
actor CoreDataChatV2SnapshotStore: ChatV2SnapshotStore {
    private enum EntityName {
        static let thread = "ChatThreadEntityV2"
        static let message = "ChatMessageEntityV2"
        static let outbox = "ChatOutboxEntityV2"
        static let checkpoint = "ChatSyncCheckpointEntityV2"
    }

    private let coreDataStack: CoreDataStack
    private let codec: ChatV2MessageDocumentCodec
    private let logger: Logger

    init(
        coreDataStack: CoreDataStack,
        codec: ChatV2MessageDocumentCodec = ChatV2MessageDocumentCodec(),
        logger: Logger = ConsoleLogger()
    ) {
        self.coreDataStack = coreDataStack
        self.codec = codec
        self.logger = logger
    }

    func loadThreads(ownerAccountID: Int64) async throws -> [ChatV2ThreadRecord] {
        logger.debug("对话V2 读取线程列表 accountID=\(ownerAccountID)", module: .general)
        return try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            request.predicate = NSPredicate(format: "ownerAccountID == %lld", ownerAccountID)
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return try context.fetch(request).compactMap(Self.toThreadRecord)
        }
    }

    func loadMessages(threadID: UUID, limit: Int?) async throws -> [ChatV2MessageRecord] {
        logger.debug("对话V2 读取消息 thread=\(shortID(threadID))", module: .general)
        return try await coreDataStack.performBackgroundTask { [codec] context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
            request.predicate = NSPredicate(format: "threadID == %@", threadID as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            if let limit, limit > 0 {
                request.fetchLimit = limit
            }
            return try context.fetch(request).compactMap { try Self.toMessageRecord($0, codec: codec) }
        }
    }

    func insertThread(_ thread: ChatV2ThreadRecord) async throws {
        logger.info("对话V2 新建线程 id=\(shortID(thread.id)) title=\(thread.title)", module: .general)
        try await coreDataStack.performBackgroundTask { context in
            let object = NSEntityDescription.insertNewObject(forEntityName: EntityName.thread, into: context)
            Self.fillThread(object: object, with: thread)
        }
    }

    func upsertThread(_ thread: ChatV2ThreadRecord) async throws {
        logger.debug("对话V2 Upsert 线程 id=\(shortID(thread.id))", module: .general)
        try await coreDataStack.performBackgroundTask { context in
            let object = try Self.fetchOrInsert(
                context: context,
                entityName: EntityName.thread,
                id: thread.id
            )
            Self.fillThread(object: object, with: thread)
        }
    }

    func insertDraftMessage(_ message: ChatV2MessageRecord) async throws {
        logger.info("对话V2 写入草稿消息 id=\(shortID(message.id)) status=\(message.status.rawValue)", module: .general)
        try await upsertMessage(message)
    }

    func commitMessageSnapshot(_ message: ChatV2MessageRecord) async throws {
        logger.info("对话V2 提交最终消息快照 id=\(shortID(message.id)) version=\(message.version)", module: .general)
        try await upsertMessage(message)
    }

    func replaceRemoteSnapshot(_ message: ChatV2MessageRecord) async throws {
        logger.info("对话V2 覆盖远端快照 id=\(shortID(message.id))", module: .general)
        try await upsertMessage(message)
    }

    func markMessageFailed(messageID: UUID, errorText: String?) async throws {
        logger.warning("对话V2 标记消息失败 id=\(shortID(messageID)) error=\(errorText ?? "-")", module: .general)
        try await coreDataStack.performBackgroundTask { context in
            guard let object = try Self.fetch(context: context, entityName: EntityName.message, id: messageID) else { return }
            object.setValue(ChatV2MessageStatus.failed.rawValue, forKey: "statusRaw")
            object.setValue(errorText, forKey: "errorText")
            object.setValue(Date(), forKey: "updatedAt")
        }
    }

    func tombstoneMessage(messageID: UUID, updatedAt: Date) async throws {
        logger.info("对话V2 标记消息墓碑 id=\(shortID(messageID))", module: .general)
        try await coreDataStack.performBackgroundTask { context in
            guard let object = try Self.fetch(context: context, entityName: EntityName.message, id: messageID) else { return }
            object.setValue(ChatV2MessageStatus.tombstoned.rawValue, forKey: "statusRaw")
            object.setValue(updatedAt, forKey: "updatedAt")
        }
    }

    func enqueueOutbox(_ record: ChatV2OutboxRecord) async throws {
        logger.debug("对话V2 写入 Outbox id=\(shortID(record.id)) message=\(shortID(record.messageID))", module: .general)
        try await upsertOutbox(record)
    }

    func updateOutbox(_ record: ChatV2OutboxRecord) async throws {
        logger.debug("对话V2 更新 Outbox id=\(shortID(record.id)) status=\(record.status.rawValue)", module: .general)
        try await upsertOutbox(record)
    }

    func loadPendingOutbox(limit: Int?) async throws -> [ChatV2OutboxRecord] {
        logger.debug("对话V2 读取待发送 Outbox", module: .general)
        return try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.outbox)
            request.predicate = NSPredicate(format: "statusRaw IN %@", [ChatV2OutboxRecord.Status.pending.rawValue, ChatV2OutboxRecord.Status.failed.rawValue])
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            if let limit, limit > 0 {
                request.fetchLimit = limit
            }
            return try context.fetch(request).compactMap(Self.toOutboxRecord)
        }
    }

    func saveCheckpoint(_ checkpoint: ChatV2SyncCheckpoint) async throws {
        logger.debug("对话V2 保存同步游标 scope=\(checkpoint.scopeKey)", module: .general)
        try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.checkpoint)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "scopeKey == %@", checkpoint.scopeKey)
            let object = try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.checkpoint, into: context)
            object.setValue(checkpoint.id, forKey: "id")
            object.setValue(checkpoint.scopeKey, forKey: "scopeKey")
            object.setValue(checkpoint.cursor, forKey: "cursor")
            object.setValue(checkpoint.updatedAt, forKey: "updatedAt")
        }
    }

    func loadCheckpoint(scopeKey: String) async throws -> ChatV2SyncCheckpoint? {
        logger.debug("对话V2 读取同步游标 scope=\(scopeKey)", module: .general)
        return try await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.checkpoint)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "scopeKey == %@", scopeKey)
            return try context.fetch(request).first.flatMap(Self.toCheckpoint)
        }
    }

    private func upsertMessage(_ message: ChatV2MessageRecord) async throws {
        try await coreDataStack.performBackgroundTask { [codec] context in
            let object = try Self.fetchOrInsert(context: context, entityName: EntityName.message, id: message.id)
            let encodedDocument = try codec.encode(message.document)
            object.setValue(message.id, forKey: "id")
            object.setValue(message.ownerAccountID, forKey: "ownerAccountID")
            object.setValue(message.threadID, forKey: "threadID")
            object.setValue(message.clientMessageID, forKey: "clientMessageID")
            object.setValue(message.serverMessageID, forKey: "serverMessageID")
            object.setValue(message.role.rawValue, forKey: "roleRaw")
            object.setValue(message.status.rawValue, forKey: "statusRaw")
            object.setValue(encodedDocument, forKey: "documentData")
            object.setValue(message.errorText, forKey: "errorText")
            object.setValue(message.version, forKey: "version")
            object.setValue(message.createdAt, forKey: "createdAt")
            object.setValue(message.updatedAt, forKey: "updatedAt")
            object.setValue(message.committedAt, forKey: "committedAt")
        }
    }

    private func upsertOutbox(_ record: ChatV2OutboxRecord) async throws {
        try await coreDataStack.performBackgroundTask { context in
            let object = try Self.fetchOrInsert(context: context, entityName: EntityName.outbox, id: record.id)
            object.setValue(record.id, forKey: "id")
            object.setValue(record.messageID, forKey: "messageID")
            object.setValue(record.threadID, forKey: "threadID")
            object.setValue(record.requestEnvelopeData, forKey: "requestEnvelopeData")
            object.setValue(record.status.rawValue, forKey: "statusRaw")
            object.setValue(record.retryCount, forKey: "retryCount")
            object.setValue(record.createdAt, forKey: "createdAt")
            object.setValue(record.updatedAt, forKey: "updatedAt")
        }
    }

    private static func fillThread(object: NSManagedObject, with record: ChatV2ThreadRecord) {
        object.setValue(record.id, forKey: "id")
        object.setValue(record.ownerAccountID, forKey: "ownerAccountID")
        object.setValue(record.title, forKey: "title")
        object.setValue(record.scenario.rawValue, forKey: "scenarioRaw")
        object.setValue(record.memberID, forKey: "memberID")
        object.setValue(record.status.rawValue, forKey: "statusRaw")
        object.setValue(record.createdAt, forKey: "createdAt")
        object.setValue(record.updatedAt, forKey: "updatedAt")
        object.setValue(record.lastSyncedAt, forKey: "lastSyncedAt")
    }

    private static func toThreadRecord(_ object: NSManagedObject) -> ChatV2ThreadRecord? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let title = object.value(forKey: "title") as? String,
            let scenarioRaw = object.value(forKey: "scenarioRaw") as? String,
            let scenario = ChatV2Scenario(rawValue: scenarioRaw),
            let statusRaw = object.value(forKey: "statusRaw") as? String,
            let status = ChatV2ThreadStatus(rawValue: statusRaw),
            let createdAt = object.value(forKey: "createdAt") as? Date,
            let updatedAt = object.value(forKey: "updatedAt") as? Date
        else {
            return nil
        }
        let ownerAccountID = object.value(forKey: "ownerAccountID") as? Int64 ?? 0
        let memberID = object.value(forKey: "memberID") as? Int64
        let lastSyncedAt = object.value(forKey: "lastSyncedAt") as? Date
        return ChatV2ThreadRecord(
            id: id,
            ownerAccountID: ownerAccountID,
            title: title,
            scenario: scenario,
            memberID: memberID,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastSyncedAt: lastSyncedAt
        )
    }

    private static func toMessageRecord(
        _ object: NSManagedObject,
        codec: ChatV2MessageDocumentCodec
    ) throws -> ChatV2MessageRecord? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let threadID = object.value(forKey: "threadID") as? UUID,
            let clientMessageID = object.value(forKey: "clientMessageID") as? UUID,
            let roleRaw = object.value(forKey: "roleRaw") as? String,
            let role = ChatV2Role(rawValue: roleRaw),
            let statusRaw = object.value(forKey: "statusRaw") as? String,
            let status = ChatV2MessageStatus(rawValue: statusRaw),
            let createdAt = object.value(forKey: "createdAt") as? Date,
            let updatedAt = object.value(forKey: "updatedAt") as? Date
        else {
            return nil
        }
        let ownerAccountID = object.value(forKey: "ownerAccountID") as? Int64 ?? 0
        let serverMessageID = object.value(forKey: "serverMessageID") as? String
        let errorText = object.value(forKey: "errorText") as? String
        let version = object.value(forKey: "version") as? Int ?? 1
        let committedAt = object.value(forKey: "committedAt") as? Date
        let documentData = object.value(forKey: "documentData") as? Data ?? Data()
        let document = documentData.isEmpty ? .empty : try codec.decode(documentData)
        return ChatV2MessageRecord(
            id: id,
            threadID: threadID,
            ownerAccountID: ownerAccountID,
            clientMessageID: clientMessageID,
            serverMessageID: serverMessageID,
            role: role,
            status: status,
            document: document,
            errorText: errorText,
            version: version,
            createdAt: createdAt,
            updatedAt: updatedAt,
            committedAt: committedAt
        )
    }

    private static func toOutboxRecord(_ object: NSManagedObject) -> ChatV2OutboxRecord? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let messageID = object.value(forKey: "messageID") as? UUID,
            let threadID = object.value(forKey: "threadID") as? UUID,
            let requestEnvelopeData = object.value(forKey: "requestEnvelopeData") as? Data,
            let statusRaw = object.value(forKey: "statusRaw") as? String,
            let status = ChatV2OutboxRecord.Status(rawValue: statusRaw),
            let createdAt = object.value(forKey: "createdAt") as? Date,
            let updatedAt = object.value(forKey: "updatedAt") as? Date
        else {
            return nil
        }
        let retryCount = object.value(forKey: "retryCount") as? Int ?? 0
        return ChatV2OutboxRecord(
            id: id,
            messageID: messageID,
            threadID: threadID,
            requestEnvelopeData: requestEnvelopeData,
            status: status,
            retryCount: retryCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func toCheckpoint(_ object: NSManagedObject) -> ChatV2SyncCheckpoint? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let scopeKey = object.value(forKey: "scopeKey") as? String,
            let updatedAt = object.value(forKey: "updatedAt") as? Date
        else {
            return nil
        }
        return ChatV2SyncCheckpoint(
            id: id,
            scopeKey: scopeKey,
            cursor: object.value(forKey: "cursor") as? String,
            updatedAt: updatedAt
        )
    }

    private static func fetch(
        context: NSManagedObjectContext,
        entityName: String,
        id: UUID
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    private static func fetchOrInsert(
        context: NSManagedObjectContext,
        entityName: String,
        id: UUID
    ) throws -> NSManagedObject {
        if let existing = try fetch(context: context, entityName: entityName, id: id) {
            return existing
        }
        return NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
