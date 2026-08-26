import CoreData
import Foundation

/// 知识库 `KnowledgeRepository` 实现。
///
/// - 文档正文存 `KnowledgeDocumentEntity`，按段落切块写入 `KnowledgeChunkEntity` 供本地检索；向量化后切块带 `vectorData`。
/// - 检索：可选查询向量 + 切块余弦相似度，无向量或未嵌入时回退词法打分（与 `ToolHub.search_knowledge_bag` 共用）。
/// - 后台上下文写入由 `CoreDataStack.performBackgroundTask` 统一提交，避免主线程阻塞。

/// CoreData 知识库仓库实现
/// 实现 KnowledgeRepository 协议，负责所有知识库数据的 CRUD、检索、向量存储
nonisolated final class CoreDataKnowledgeRepository: KnowledgeRepository, @unchecked Sendable {

    // MARK: - 常量定义
    private enum Field {
        static let ownerAccountID = "ownerAccountID"
    }

    /// 知识同步游标复用现有 `ChatSyncCursorEntity` 表（不同 key 命名空间），不新建 Cursor 实体。
    private static let cursorKey = "knowledge.document.cursor.v1"

    // MARK: - 依赖
    private let coreDataStack: CoreDataStack          // CoreData 栈管理
    private let snapshotStore: SessionSnapshotStore   // 用户会话信息（账号ID）
    private let logger: Logger                        // 日志工具

    // MARK: - 初始化
    init(
        coreDataStack: CoreDataStack,
        snapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        logger: Logger = ConsoleLogger()
    ) {
        self.coreDataStack = coreDataStack
        self.snapshotStore = snapshotStore
        self.logger = logger
    }

    // MARK: - 加载文档列表（支持搜索）
    func loadDocuments(matching query: String?) async throws -> [KnowledgeDocument] {
        let accountID = try await requireAccountID()
        return try await coreDataStack.performBackgroundTask { context in
            let request = KnowledgeDocumentEntity.fetchRequest()
            // 按更新时间倒序
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            var predicates = [self.ownerPredicate(accountID), self.notDeletedPredicate()]

            // 搜索条件：标题/内容/摘要 包含关键词
            if let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                predicates.append(NSPredicate(
                    format: "title CONTAINS[cd] %@ OR content CONTAINS[cd] %@ OR excerpt CONTAINS[cd] %@",
                    trimmed, trimmed, trimmed
                ))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            // 转换为领域模型返回
            return try context.fetch(request).compactMap { $0.toDomain() }
        }
    }

    // MARK: - 根据 ID 加载单个文档
    func loadDocument(id: UUID) async throws -> KnowledgeDocument? {
        let accountID = try await requireAccountID()
        return try await coreDataStack.performBackgroundTask { context in
            try self.fetchDocumentEntity(id: id, ownerAccountID: accountID, context: context)?.toDomain()
        }
    }

    // MARK: - 创建文档
    func createDocument(_ draft: KnowledgeDocumentDraft) async throws -> KnowledgeDocument {
        let accountID = try await requireAccountID()
        let prepared = try validate(draft) // 校验并清理输入
        let document = try await coreDataStack.performBackgroundTask { context in
            let now = Date()
            let entity = KnowledgeDocumentEntity(context: context)
            entity.id = UUID()
            entity.ownerAccountID = accountID
            entity.createdAt = now
            entity.isEmbeddingIndexed = false // 新建文档无向量索引
            entity.isRemoteDeleted = false
            entity.serverRevision = 0

            // 应用草稿数据
            self.apply(prepared, to: entity, updatedAt: now)
            // 重建文本切块
            try self.rebuildChunks(for: entity, ownerAccountID: accountID, context: context)

            // 本地事实 + Outbox 入队处于同一事务（工单 5.2），本地写入不等待网络。
            guard let documentID = entity.id else {
                throw self.knowledgeError("知识文档缺少 ID，无法入队同步")
            }
            let payload = self.makeOutboxPayload(for: entity)
            _ = try self.upsertOutboxRow(
                documentID: documentID,
                ownerAccountID: accountID,
                intent: .create,
                knownServerRevision: 0,
                payload: payload,
                context: context
            )
            entity.lastSyncStateRaw = KnowledgeSyncState.pending.rawValue

            guard let document = entity.toDomain() else {
                throw self.knowledgeError("知识文档创建后无法生成领域对象")
            }
            return document
        }
        NotificationCenter.default.post(name: .sparkKnowledgeDatabaseDidChange, object: nil)
        return document
    }

    // MARK: - 更新文档
    func updateDocument(id: UUID, draft: KnowledgeDocumentDraft) async throws -> KnowledgeDocument {
        let accountID = try await requireAccountID()
        let prepared = try validate(draft)
        let document = try await coreDataStack.performBackgroundTask { context in
            guard let entity = try self.fetchDocumentEntity(id: id, ownerAccountID: accountID, context: context) else {
                throw self.knowledgeError("未找到要更新的知识文档")
            }
            let contentBefore = entity.content ?? ""
            let hasMeaningfulChange = contentBefore != prepared.content
                || (entity.title ?? "") != prepared.title
                || (entity.scopeRaw ?? "") != prepared.scope.rawValue
                || entity.boundModelID != prepared.boundModelID

            self.apply(prepared, to: entity, updatedAt: Date())
            // 仅正文变化时重建切块；否则保留现有切块与向量索引（避免无意义 save / load 触发清索引）
            if contentBefore != prepared.content {
                try self.rebuildChunks(for: entity, ownerAccountID: accountID, context: context)
            }

            if hasMeaningfulChange {
                let payload = self.makeOutboxPayload(for: entity)
                let stillNeedsNetwork = try self.upsertOutboxRow(
                    documentID: id,
                    ownerAccountID: accountID,
                    intent: .update,
                    knownServerRevision: entity.serverRevision,
                    payload: payload,
                    context: context
                )
                entity.lastSyncStateRaw = stillNeedsNetwork ? KnowledgeSyncState.pending.rawValue : entity.lastSyncStateRaw
            }

            guard let document = entity.toDomain() else {
                throw self.knowledgeError("知识文档更新后无法生成领域对象")
            }
            return document
        }
        NotificationCenter.default.post(name: .sparkKnowledgeDatabaseDidChange, object: nil)
        return document
    }

    // MARK: - 重建文档索引（清空向量，重新切块）
    func rebuildIndex(id: UUID) async throws -> KnowledgeDocument {
        let accountID = try await requireAccountID()
        return try await coreDataStack.performBackgroundTask { context in
            guard let entity = try self.fetchDocumentEntity(id: id, ownerAccountID: accountID, context: context) else {
                throw self.knowledgeError("未找到要重建索引的知识文档")
            }
            entity.updatedAt = Date()
            try self.rebuildChunks(for: entity, ownerAccountID: accountID, context: context)

            guard let document = entity.toDomain() else {
                throw self.knowledgeError("知识文档重建索引后无法生成领域对象")
            }
            return document
        }
    }

    // MARK: - 删除文档
    func deleteDocument(id: UUID) async throws {
        let accountID = try await requireAccountID()
        try await coreDataStack.performBackgroundTask { context in
            guard let entity = try self.fetchDocumentEntity(id: id, ownerAccountID: accountID, context: context) else { return }
            // 从未上云的文档删除：Outbox 层会就地清空 create 记录，不产生网络请求。
            _ = try self.upsertOutboxRow(
                documentID: id,
                ownerAccountID: accountID,
                intent: .delete,
                knownServerRevision: entity.serverRevision,
                payload: .empty,
                context: context
            )
            // 先删除所有切块
            try self.deleteChunks(documentID: id, ownerAccountID: accountID, context: context)
            // 再删除文档：本地立即生效；已上云的文档由 Outbox 的 delete mutation 异步传播给服务端。
            context.delete(entity)
        }
        NotificationCenter.default.post(name: .sparkKnowledgeDatabaseDidChange, object: nil)
    }

    // MARK: - 多设备同步：Outbox 读取与状态转换

    func loadPendingOutbox(limit: Int) async -> [KnowledgeOutboxRecord] {
        let accountID = try? await requireAccountID()
        guard let accountID else { return [] }
        return (try? await coreDataStack.performBackgroundTask { context in
            let request = KnowledgeSyncOutboxEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            request.fetchLimit = max(limit, 1)
            let now = Date()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                self.ownerPredicate(accountID),
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "stateRaw == %@", KnowledgeOutboxState.pending.rawValue),
                    NSPredicate(format: "stateRaw == %@", KnowledgeOutboxState.sending.rawValue),
                    NSCompoundPredicate(andPredicateWithSubpredicates: [
                        NSPredicate(format: "stateRaw == %@", KnowledgeOutboxState.failedRetryable.rawValue),
                        NSCompoundPredicate(orPredicateWithSubpredicates: [
                            NSPredicate(format: "nextAttemptAt == nil"),
                            NSPredicate(format: "nextAttemptAt <= %@", now as NSDate),
                        ]),
                    ]),
                ]),
            ])
            return try context.fetch(request).compactMap { $0.toRecord() }
        }) ?? []
    }

    func documentIDsWithActiveOutbox() async -> Set<UUID> {
        let accountID = try? await requireAccountID()
        guard let accountID else { return [] }
        return (try? await coreDataStack.performBackgroundTask { context in
            let request = KnowledgeSyncOutboxEntity.fetchRequest()
            request.predicate = self.ownerPredicate(accountID)
            return Set(try context.fetch(request).compactMap { $0.documentID })
        }) ?? []
    }

    func markOutboxSending(mutationIDs: [UUID]) async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            let request = KnowledgeSyncOutboxEntity.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                self.ownerPredicate(accountID),
                NSPredicate(format: "mutationID IN %@", mutationIDs),
            ])
            for row in try context.fetch(request) {
                row.stateRaw = KnowledgeOutboxState.sending.rawValue
                row.updatedAt = Date()
            }
        }
    }

    func markOutboxAcceptedAndApplyServerFields(
        mutationID: UUID,
        documentID: UUID,
        revision: Int64,
        serverUpdatedAt: Date,
        contentHash: String
    ) async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            try self.removeOutboxRow(mutationID: mutationID, ownerAccountID: accountID, context: context)
            guard let entity = try self.fetchDocumentEntityIncludingDeleted(id: documentID, ownerAccountID: accountID, context: context) else {
                return
            }
            entity.serverRevision = revision
            entity.serverUpdatedAt = serverUpdatedAt
            entity.contentHash = contentHash
            entity.lastSyncSucceededAt = Date()
            entity.lastSyncAttemptAt = Date()
            entity.lastSyncErrorCode = nil
            let hasOtherOutbox = try self.hasActiveOutboxRow(documentID: documentID, ownerAccountID: accountID, context: context)
            entity.lastSyncStateRaw = hasOtherOutbox ? KnowledgeSyncState.pending.rawValue : KnowledgeSyncState.synced.rawValue
        }
    }

    func resolveConflictWithServerSnapshot(mutationID: UUID, snapshot: KnowledgeRemoteDocumentSnapshot) async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            try self.removeOutboxRow(mutationID: mutationID, ownerAccountID: accountID, context: context)
            try self.applySnapshot(snapshot, ownerAccountID: accountID, context: context, resultingState: .resolvedByServer)
        }
    }

    func markOutboxFailedRetryable(mutationID: UUID, errorCode: String, nextAttemptAt: Date) async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            guard let row = try self.fetchOutboxRow(mutationID: mutationID, ownerAccountID: accountID, context: context) else { return }
            row.stateRaw = KnowledgeOutboxState.failedRetryable.rawValue
            row.attemptCount += 1
            row.lastErrorCode = errorCode
            row.nextAttemptAt = nextAttemptAt
            row.updatedAt = Date()
            guard let documentID = row.documentID,
                  let entity = try self.fetchDocumentEntityIncludingDeleted(id: documentID, ownerAccountID: accountID, context: context)
            else { return }
            entity.lastSyncStateRaw = KnowledgeSyncState.failedRetryable.rawValue
            entity.lastSyncAttemptAt = Date()
            entity.lastSyncErrorCode = errorCode
        }
    }

    func markOutboxFailedPermanent(mutationID: UUID, errorCode: String) async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            guard let row = try self.fetchOutboxRow(mutationID: mutationID, ownerAccountID: accountID, context: context) else { return }
            row.stateRaw = KnowledgeOutboxState.failedPermanent.rawValue
            row.lastErrorCode = errorCode
            row.updatedAt = Date()
            guard let documentID = row.documentID,
                  let entity = try self.fetchDocumentEntityIncludingDeleted(id: documentID, ownerAccountID: accountID, context: context)
            else { return }
            entity.lastSyncStateRaw = KnowledgeSyncState.failedPermanent.rawValue
            entity.lastSyncAttemptAt = Date()
            entity.lastSyncErrorCode = errorCode
        }
    }

    @discardableResult
    func applyRemoteDocuments(_ documents: [KnowledgeRemoteDocumentSnapshot]) async -> [UUID] {
        guard let accountID = try? await requireAccountID() else { return [] }
        return (try? await coreDataStack.performBackgroundTask { context in
            let activeOutboxIDs = Set(try context.fetch(self.allOutboxRequest(ownerAccountID: accountID)).compactMap { $0.documentID })
            var changedContentDocumentIDs: [UUID] = []
            for snapshot in documents where activeOutboxIDs.contains(snapshot.id) == false {
                let changed = try self.applySnapshot(snapshot, ownerAccountID: accountID, context: context, resultingState: .synced)
                if changed { changedContentDocumentIDs.append(snapshot.id) }
            }
            return changedContentDocumentIDs
        }) ?? []
    }

    func loadSyncCursor() async -> String? {
        guard let accountID = try? await requireAccountID() else { return nil }
        return try? await coreDataStack.performBackgroundTask { context in
            self.fetchCursorValue(ownerAccountID: accountID, context: context)
        }
    }

    func saveSyncCursor(_ value: String?) async {
        guard let accountID = try? await requireAccountID() else { return }
        _ = try? await coreDataStack.performBackgroundTask { context in
            self.writeCursorValue(value, ownerAccountID: accountID, context: context)
        }
    }

    // MARK: - 同步内部辅助

    private func makeOutboxPayload(for entity: KnowledgeDocumentEntity) -> KnowledgeOutboxPayload {
        let now = entity.updatedAt ?? Date()
        return KnowledgeOutboxPayload(
            knowledgeBaseID: entity.knowledgeBaseID,
            title: entity.title ?? "",
            content: entity.content ?? "",
            excerpt: entity.excerpt ?? "",
            scope: KnowledgeDocumentScope(rawValue: entity.scopeRaw ?? "") ?? .personal,
            boundModelID: entity.boundModelID,
            source: KnowledgeDocumentSource(rawValue: entity.sourceRaw ?? "") ?? .user,
            clientCreatedAt: entity.createdAt ?? now,
            clientUpdatedAt: now
        )
    }

    /// Outbox 压缩规则（工单 5.4）：同一 `document_id` 内合并尚未发送/未 ACK 的队列。
    /// 返回值：本次写入之后是否仍需要联网同步（`false` = 已就地清空，例如 create→delete）。
    @discardableResult
    private func upsertOutboxRow(
        documentID: UUID,
        ownerAccountID: Int64,
        intent: KnowledgeSyncOperation,
        knownServerRevision: Int64,
        payload: KnowledgeOutboxPayload,
        context: NSManagedObjectContext
    ) throws -> Bool {
        guard let existing = try fetchOutboxRow(documentID: documentID, ownerAccountID: ownerAccountID, context: context) else {
            // 从未上云（serverRevision == 0）且从没有排队过：任何写操作首先都应作为 create；
            // 从未上云的删除则完全是本地事务，无需联网。
            if knownServerRevision == 0 {
                if intent == .delete { return false }
                return try insertOutboxRow(documentID: documentID, ownerAccountID: ownerAccountID, operation: .create, baseRevision: 0, payload: payload, context: context)
            }
            let baseRevision = intent == .create ? 0 : knownServerRevision
            return try insertOutboxRow(documentID: documentID, ownerAccountID: ownerAccountID, operation: intent, baseRevision: baseRevision, payload: payload, context: context)
        }

        let currentOperation = KnowledgeSyncOperation(rawValue: existing.operationRaw ?? "") ?? .update

        switch (currentOperation, intent) {
        case (.create, .delete):
            // create→delete 且从未 ACK：本地直接清除，不访问服务端。
            context.delete(existing)
            return false
        case (.create, _):
            existing.payloadData = payload.encoded()
        case (.update, .delete):
            existing.operationRaw = KnowledgeSyncOperation.delete.rawValue
            existing.payloadData = KnowledgeOutboxPayload.empty.encoded()
        case (.update, _):
            existing.payloadData = payload.encoded()
        case (.delete, .delete):
            break // 原 mutation 重放，不生成新删除事件
        case (.delete, _):
            break // 已排队删除，忽略后续编辑意图
        case (.restore, _):
            existing.payloadData = payload.encoded()
        }

        existing.stateRaw = KnowledgeOutboxState.pending.rawValue
        existing.lastErrorCode = nil
        existing.updatedAt = Date()
        return true
    }

    private func insertOutboxRow(
        documentID: UUID,
        ownerAccountID: Int64,
        operation: KnowledgeSyncOperation,
        baseRevision: Int64,
        payload: KnowledgeOutboxPayload,
        context: NSManagedObjectContext
    ) throws -> Bool {
        let row = KnowledgeSyncOutboxEntity(context: context)
        row.mutationID = UUID()
        row.ownerAccountID = ownerAccountID
        row.documentID = documentID
        row.operationRaw = operation.rawValue
        row.baseRevision = baseRevision
        row.payloadData = payload.encoded()
        row.requestHash = ""
        row.stateRaw = KnowledgeOutboxState.pending.rawValue
        row.attemptCount = 0
        let now = Date()
        row.createdAt = now
        row.updatedAt = now
        return true
    }

    private func fetchOutboxRow(
        documentID: UUID,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> KnowledgeSyncOutboxEntity? {
        let request = KnowledgeSyncOutboxEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "documentID == %@", documentID as CVarArg),
        ])
        return try context.fetch(request).first
    }

    private func fetchOutboxRow(
        mutationID: UUID,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> KnowledgeSyncOutboxEntity? {
        let request = KnowledgeSyncOutboxEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "mutationID == %@", mutationID as CVarArg),
        ])
        return try context.fetch(request).first
    }

    private func removeOutboxRow(mutationID: UUID, ownerAccountID: Int64, context: NSManagedObjectContext) throws {
        if let row = try fetchOutboxRow(mutationID: mutationID, ownerAccountID: ownerAccountID, context: context) {
            context.delete(row)
        }
    }

    private func hasActiveOutboxRow(documentID: UUID, ownerAccountID: Int64, context: NSManagedObjectContext) throws -> Bool {
        try fetchOutboxRow(documentID: documentID, ownerAccountID: ownerAccountID, context: context) != nil
    }

    private func allOutboxRequest(ownerAccountID: Int64) -> NSFetchRequest<KnowledgeSyncOutboxEntity> {
        let request = KnowledgeSyncOutboxEntity.fetchRequest()
        request.predicate = ownerPredicate(ownerAccountID)
        return request
    }

    /// 应用服务端权威快照到本地主文档；返回是否需要重建本地 Chunk（正文/hash 变化且非删除）。
    @discardableResult
    private func applySnapshot(
        _ snapshot: KnowledgeRemoteDocumentSnapshot,
        ownerAccountID: Int64,
        context: NSManagedObjectContext,
        resultingState: KnowledgeSyncState
    ) throws -> Bool {
        let entity = try fetchDocumentEntityIncludingDeleted(id: snapshot.id, ownerAccountID: ownerAccountID, context: context)
            ?? KnowledgeDocumentEntity(context: context)
        if entity.id == nil {
            entity.id = snapshot.id
            entity.ownerAccountID = ownerAccountID
            entity.createdAt = snapshot.serverUpdatedAt
            entity.isEmbeddingIndexed = false
        }

        let contentChanged = entity.contentHash != snapshot.contentHash && snapshot.isDeleted == false

        entity.knowledgeBaseID = snapshot.knowledgeBaseID
        entity.title = snapshot.title
        entity.content = snapshot.content
        entity.excerpt = snapshot.excerpt
        entity.scopeRaw = snapshot.scope.rawValue
        entity.boundModelID = snapshot.boundModelID
        entity.sourceRaw = snapshot.source.rawValue
        entity.contentHash = snapshot.contentHash
        entity.serverRevision = snapshot.revision
        entity.serverUpdatedAt = snapshot.serverUpdatedAt
        entity.isRemoteDeleted = snapshot.isDeleted
        entity.deletedAt = snapshot.deletedAt
        entity.updatedAt = snapshot.serverUpdatedAt
        entity.lastSyncStateRaw = resultingState.rawValue
        entity.lastSyncSucceededAt = Date()
        entity.lastSyncErrorCode = nil

        if snapshot.isDeleted {
            try deleteChunks(documentID: snapshot.id, ownerAccountID: ownerAccountID, context: context)
            entity.chunkCount = 0
            entity.isEmbeddingIndexed = false
            entity.lastEmbeddingModelName = nil
            return false
        }

        if contentChanged {
            // 远端正文已变化：事务内删除旧 Chunk、按本机算法重建文本 Chunk，vectorData 置空；
            // Embedding 重建由调用方在合并事务之后异步调度（工单 8.4），失败可词法降级。
            try rebuildChunks(for: entity, ownerAccountID: ownerAccountID, context: context)
        }

        return contentChanged
    }

    private func fetchCursorValue(ownerAccountID: Int64, context: NSManagedObjectContext) -> String? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ChatSyncCursorEntity")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "key == %@", Self.cursorKey),
        ])
        guard let object = try? context.fetch(request).first else { return nil }
        return object.value(forKey: "value") as? String
    }

    private func writeCursorValue(_ value: String?, ownerAccountID: Int64, context: NSManagedObjectContext) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ChatSyncCursorEntity")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "key == %@", Self.cursorKey),
        ])
        guard let value else {
            if let existing = try? context.fetch(request).first {
                context.delete(existing)
            }
            return
        }
        let object = (try? context.fetch(request).first)
            ?? NSEntityDescription.insertNewObject(forEntityName: "ChatSyncCursorEntity", into: context)
        object.setValue(ownerAccountID, forKey: Field.ownerAccountID)
        object.setValue(Self.cursorKey, forKey: "key")
        object.setValue(value, forKey: "value")
        object.setValue(Date(), forKey: "updatedAt")
    }

    // MARK: - 判断是否存在已向量索引的切块
    func hasVectorIndexedChunks() async throws -> Bool {
        let accountID = try await requireAccountID()
        return try await coreDataStack.performBackgroundTask { context in
            let request = KnowledgeChunkEntity.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                self.ownerPredicate(accountID),
                NSPredicate(format: "vectorData != nil"),
            ])
            return try context.fetch(request).isEmpty == false
        }
    }

    // MARK: - 用向量嵌入覆盖文档切块（构建向量索引）
    func replaceDocumentChunksWithEmbeddings(
        documentID: UUID,
        chunkTexts: [String],
        embeddings: [[Float]],
        modelName: String
    ) async throws -> KnowledgeDocument {
        guard chunkTexts.count == embeddings.count else {
            throw knowledgeError("嵌入向量数量与文本块数量不一致")
        }
        let accountID = try await requireAccountID()
        return try await coreDataStack.performBackgroundTask { context in
            guard let entity = try self.fetchDocumentEntity(id: documentID, ownerAccountID: accountID, context: context) else {
                throw self.knowledgeError("未找到要写入向量索引的知识文档")
            }
            // 删除旧切块
            try self.deleteChunks(documentID: documentID, ownerAccountID: accountID, context: context)

            let now = Date()
            // 批量创建带向量的新切块
            for (index, text) in chunkTexts.enumerated() {
                let chunk = KnowledgeChunkEntity(context: context)
                chunk.id = UUID()
                chunk.ownerAccountID = accountID
                chunk.documentID = documentID
                chunk.sequence = Int32(index)
                chunk.content = text
                chunk.vectorData = KnowledgeVectorCoding.encode(embeddings[index]) // 向量编码
                chunk.createdAt = now
                chunk.updatedAt = now
            }

            // 更新文档索引状态
            entity.chunkCount = Int32(chunkTexts.count)
            entity.isEmbeddingIndexed = true
            entity.lastEmbeddingModelName = modelName
            entity.updatedAt = now

            guard let document = entity.toDomain() else {
                throw self.knowledgeError("写入向量索引后无法生成领域对象")
            }
            return document
        }
    }

    // MARK: - 混合检索：关键词搜索 + 语义向量搜索（RAG核心）
    func search(query: String, limit: Int, queryEmbedding: [Float]?) async throws -> [KnowledgeSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let accountID = try await requireAccountID()

        return try await coreDataStack.performBackgroundTask { context in
            // 加载所有文档和切块
            let documentsRequest = KnowledgeDocumentEntity.fetchRequest()
            documentsRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                self.ownerPredicate(accountID), self.notDeletedPredicate(),
            ])
            let documents = try context.fetch(documentsRequest)

            let chunkRequest = KnowledgeChunkEntity.fetchRequest()
            chunkRequest.predicate = self.ownerPredicate(accountID)
            let chunks = try context.fetch(chunkRequest)

            // 1. 关键词检索（词法匹配）
            let lexical = self.lexicalSearchMatches(
                documents: documents,
                chunks: chunks,
                query: trimmed
            )

            // 2. 判断是否启用语义检索（有向量且传入了查询向量）
            let useSemantic: Bool = {
                guard let q = queryEmbedding, !q.isEmpty else { return false }
                return chunks.contains { $0.vectorData != nil }
            }()

            if !useSemantic {
                return self.sortedResults(from: lexical, limit: limit)
            }

            guard let qVec = queryEmbedding else {
                return self.sortedResults(from: lexical, limit: limit)
            }

            // 3. 语义检索：余弦相似度计算
            var semanticBest: [UUID: (score: Double, sequence: Int, excerpt: String, title: String)] = [:]
            for chunk in chunks {
                guard
                    let documentID = chunk.documentID,
                    let data = chunk.vectorData,
                    let content = chunk.content,
                    let vector = KnowledgeVectorCoding.decode(data),
                    vector.count == qVec.count
                else { continue }

                // 计算相似度
                let sim = Double(KnowledgeEmbeddingSimilarity.cosine(qVec, vector))
                let title = documents.first(where: { $0.id == documentID })?.title ?? "Untitled"
                let excerpt = self.bestExcerpt(in: content, query: trimmed, fallback: content)
                let seq = Int(chunk.sequence)

                // 保留每个文档相似度最高的切块
                if let existing = semanticBest[documentID] {
                    if sim > existing.score {
                        semanticBest[documentID] = (sim, seq, excerpt, title)
                    }
                } else {
                    semanticBest[documentID] = (sim, seq, excerpt, title)
                }
            }

            // 4. 合并词法 + 语义得分（加权融合）
            var merged: [UUID: KnowledgeSearchResult] = [:]
            let allIDs = Set(lexical.keys).union(semanticBest.keys)
            for id in allIDs {
                let lex = lexical[id]
                if let sem = semanticBest[id] {
                    let combined = sem.score * 100.0 + (lex?.score ?? 0) * 0.15
                    merged[id] = KnowledgeSearchResult(
                        documentID: id,
                        title: sem.title,
                        excerpt: sem.excerpt,
                        matchedChunkSequence: sem.sequence,
                        score: combined
                    )
                } else if let lex {
                    merged[id] = lex
                }
            }

            return self.sortedResults(from: merged, limit: limit)
        }
    }

    // MARK: - 关键词检索（词法匹配）
    private func lexicalSearchMatches(
        documents: [KnowledgeDocumentEntity],
        chunks: [KnowledgeChunkEntity],
        query: String
    ) -> [UUID: KnowledgeSearchResult] {
        let queryTokens = self.tokenize(query)
        var bestMatches: [UUID: KnowledgeSearchResult] = [:]

        // 匹配文档
        for document in documents {
            guard let mapped = document.toDomain() else { continue }
            let exactTitleHit = mapped.title.localizedCaseInsensitiveContains(query)
            let exactContentHit = mapped.content.localizedCaseInsensitiveContains(query)
            let baseScore = self.score(text: mapped.title, tokens: queryTokens) * 3.0
                + self.score(text: mapped.content, tokens: queryTokens)
                + (exactTitleHit ? 6.0 : 0.0)
                + (exactContentHit ? 2.0 : 0.0)

            if baseScore > 0 {
                bestMatches[mapped.id] = KnowledgeSearchResult(
                    documentID: mapped.id,
                    title: mapped.title,
                    excerpt: self.bestExcerpt(in: mapped.content, query: query, fallback: mapped.excerpt),
                    matchedChunkSequence: nil,
                    score: baseScore
                )
            }
        }

        // 匹配切块（权重更高）
        for chunk in chunks {
            guard
                let documentID = chunk.documentID,
                let content = chunk.content,
                !content.isEmpty
            else { continue }

            let tokenScore = self.score(text: content, tokens: queryTokens)
            let exactHit = content.localizedCaseInsensitiveContains(query)
            let candidateScore = tokenScore * 2.0 + (exactHit ? 4.0 : 0.0)
            guard candidateScore > 0 else { continue }

            let current = bestMatches[documentID]
            if current == nil || candidateScore > current!.score {
                let title = current?.title
                    ?? documents.first(where: { $0.id == documentID })?.title
                    ?? "Untitled"
                bestMatches[documentID] = KnowledgeSearchResult(
                    documentID: documentID,
                    title: title,
                    excerpt: self.bestExcerpt(in: content, query: query, fallback: content),
                    matchedChunkSequence: Int(chunk.sequence),
                    score: candidateScore
                )
            }
        }

        return bestMatches
    }

    // MARK: - 结果排序（按得分 + 标题）
    private func sortedResults(from map: [UUID: KnowledgeSearchResult], limit: Int) -> [KnowledgeSearchResult] {
        map.values
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.title.localizedCompare(rhs.title) == .orderedAscending
                }
                return lhs.score > rhs.score
            }
            .prefix(max(limit, 1))
            .map { $0 }
    }

    // MARK: - 根据 ID 获取文档实体
    private func fetchDocumentEntity(
        id: UUID,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> KnowledgeDocumentEntity? {
        let request = KnowledgeDocumentEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            notDeletedPredicate(),
            NSPredicate(format: "id == %@", id as CVarArg),
        ])
        return try context.fetch(request).first
    }

    /// 供同步路径使用：包含已被远端墓碑标记为删除的文档。
    private func fetchDocumentEntityIncludingDeleted(
        id: UUID,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws -> KnowledgeDocumentEntity? {
        let request = KnowledgeDocumentEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "id == %@", id as CVarArg),
        ])
        return try context.fetch(request).first
    }

    // MARK: - 校验并清理文档草稿
    private func validate(_ draft: KnowledgeDocumentDraft) throws -> KnowledgeDocumentDraft {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return KnowledgeDocumentDraft(
            title: title.isEmpty ? "Untitled Document" : title,
            content: content,
            scope: draft.scope,
            boundModelID: draft.boundModelID?.trimmingCharacters(in: .whitespacesAndNewlines),
            source: draft.source
        )
    }

    // MARK: - 将草稿数据应用到实体
    private func apply(_ draft: KnowledgeDocumentDraft, to entity: KnowledgeDocumentEntity, updatedAt: Date) {
        entity.title = draft.title
        entity.content = draft.content
        entity.excerpt = makeExcerpt(from: draft.content)
        entity.scopeRaw = draft.scope.rawValue
        entity.boundModelID = draft.boundModelID
        entity.sourceRaw = draft.source.rawValue
        entity.updatedAt = updatedAt
    }

    // MARK: - 重建文档文本切块（无向量，仅文本）
    private func rebuildChunks(
        for entity: KnowledgeDocumentEntity,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        guard let documentID = entity.id, let content = entity.content else {
            throw knowledgeError("知识文档缺少必要字段，无法重建索引")
        }
        // 清空向量索引状态
        entity.isEmbeddingIndexed = false
        entity.lastEmbeddingModelName = nil
        // 删除旧切块
        try deleteChunks(documentID: documentID, ownerAccountID: ownerAccountID, context: context)
        // 生成新切块
        let chunks = chunkContent(content)
        entity.chunkCount = Int32(chunks.count)

        let timestamp = entity.updatedAt ?? Date()
        for (index, chunkContent) in chunks.enumerated() {
            let chunk = KnowledgeChunkEntity(context: context)
            chunk.id = UUID()
            chunk.ownerAccountID = ownerAccountID
            chunk.documentID = documentID
            chunk.sequence = Int32(index)
            chunk.content = chunkContent
            chunk.vectorData = nil
            chunk.createdAt = timestamp
            chunk.updatedAt = timestamp
        }
    }

    // MARK: - 删除文档所有切块
    private func deleteChunks(
        documentID: UUID,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        let request = KnowledgeChunkEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ownerPredicate(ownerAccountID),
            NSPredicate(format: "documentID == %@", documentID as CVarArg),
        ])
        for chunk in try context.fetch(request) {
            context.delete(chunk)
        }
    }

    // MARK: - 数据归属谓词（按用户隔离）
    private func ownerPredicate(_ accountID: Int64) -> NSPredicate {
        NSPredicate(format: "\(Field.ownerAccountID) == %lld", accountID)
    }

    /// 远端墓碑隐藏本地文档，但不立即物理删除（保留 restore 契约的可能性）。
    private func notDeletedPredicate() -> NSPredicate {
        NSPredicate(format: "isRemoteDeleted == NO")
    }

    // MARK: - 获取当前登录用户ID（无则抛错）
    private func requireAccountID() async throws -> Int64 {
        if let accountID = await snapshotStore.load()?.accountID {
            return accountID
        }
        logger.warning("知识库访问被拒绝：当前无已登录用户。", module: .general)
        throw knowledgeError("当前无登录用户，无法访问知识库数据")
    }

    // MARK: - 文本智能切块（按段落、长度拆分）
    private func chunkContent(_ content: String, maxLength: Int = 480) -> [String] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let paragraphs = normalized.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var buffer = ""

        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if buffer.isEmpty {
                if trimmed.count <= maxLength {
                    buffer = trimmed
                    continue
                }
            } else if buffer.count + 2 + trimmed.count <= maxLength {
                buffer += "\n\n" + trimmed
                continue
            } else {
                chunks.append(buffer)
                buffer = ""
            }

            if trimmed.count <= maxLength {
                buffer = trimmed
                continue
            }

            var remainder = trimmed[...]
            while !remainder.isEmpty {
                let prefix = String(remainder.prefix(maxLength))
                chunks.append(prefix)
                remainder = remainder.dropFirst(prefix.count)
            }
        }

        if !buffer.isEmpty {
            chunks.append(buffer)
        }
        return chunks.isEmpty ? [content] : chunks
    }

    // MARK: - 生成摘要（截取前140字符）
    private func makeExcerpt(from content: String, limit: Int = 140) -> String {
        let compact = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > limit else { return compact }
        return String(compact.prefix(limit)) + "..."
    }

    // MARK: - 搜索分词
    private func tokenize(_ query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: - 关键词匹配评分
    private func score(text: String, tokens: [String]) -> Double {
        guard !tokens.isEmpty else { return 0 }
        let haystack = text.lowercased()
        return tokens.reduce(into: 0.0) { partial, token in
            if haystack.contains(token) {
                partial += 1.0 + Double(occurrences(of: token, in: haystack)) * 0.2
            }
        }
    }

    // MARK: - 统计关键词出现次数
    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return max(haystack.components(separatedBy: needle).count - 1, 0)
    }

    // MARK: - 生成最佳摘要（命中关键词居中）
    private func bestExcerpt(in content: String, query: String, fallback: String) -> String {
        let normalized = content.replacingOccurrences(of: "\n", with: " ")
        let lowercase = normalized.lowercased()
        let token = query.lowercased()
        guard let range = lowercase.range(of: token) else {
            return makeExcerpt(from: fallback)
        }
        let lowerBound = normalized.distance(from: normalized.startIndex, to: range.lowerBound)
        let startOffset = max(lowerBound - 60, 0)
        let start = normalized.index(normalized.startIndex, offsetBy: startOffset)
        let excerpt = String(normalized[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return makeExcerpt(from: excerpt, limit: 160)
    }

    // MARK: - 构造错误
    private func knowledgeError(_ description: String) -> NSError {
        NSError(
            domain: "SparkClient.Knowledge",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

// MARK: - Entity 与 Domain 模型转换
// Core Data 实体 → 业务领域模型 转换扩展

nonisolated private extension KnowledgeDocumentEntity {

    /// 将 Core Data 实体对象 转换为 业务层领域模型（KnowledgeDocument）
    /// - 返回值：若必填字段缺失，返回 nil；否则返回转换后的领域模型
    nonisolated func toDomain() -> KnowledgeDocument? {
        // 校验所有**必填字段**是否存在，任一缺失则转换失败
        guard
            let id,
            let title,
            let content,
            let excerpt,
            let scopeRaw,
            let sourceRaw,
            let createdAt,
            let updatedAt
        else {
            return nil
        }

        // 执行转换，枚举值使用原始值解析，失败则给默认值兜底
        return KnowledgeDocument(
            id: id,
            title: title,
            content: content,
            excerpt: excerpt,
            scope: KnowledgeDocumentScope(rawValue: scopeRaw) ?? .personal,
            boundModelID: boundModelID,
            source: KnowledgeDocumentSource(rawValue: sourceRaw) ?? .user,
            chunkCount: Int(chunkCount),
            isEmbeddingIndexed: isEmbeddingIndexed,
            lastEmbeddingModelName: lastEmbeddingModelName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            knowledgeBaseID: knowledgeBaseID,
            serverRevision: serverRevision,
            serverUpdatedAt: serverUpdatedAt,
            isDeleted: isRemoteDeleted,
            contentHash: contentHash ?? "",
            syncState: KnowledgeSyncState(rawValue: lastSyncStateRaw ?? "") ?? .localOnly,
            lastSyncErrorCode: lastSyncErrorCode
        )
    }
}

nonisolated private extension KnowledgeSyncOutboxEntity {
    /// 将 Outbox 实体转换为同步基础设施使用的领域记录。
    nonisolated func toRecord() -> KnowledgeOutboxRecord? {
        guard
            let mutationID,
            let documentID,
            let operationRaw,
            let operation = KnowledgeSyncOperation(rawValue: operationRaw)
        else {
            return nil
        }
        return KnowledgeOutboxRecord(
            mutationID: mutationID,
            documentID: documentID,
            operation: operation,
            baseRevision: baseRevision,
            payload: payloadData ?? Data(),
            requestHash: requestHash ?? "",
            attemptCount: attemptCount,
            nextAttemptAt: nextAttemptAt
        )
    }
}
