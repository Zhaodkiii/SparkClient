import CoreData
import Foundation

/// 知识库 `KnowledgeRepository` 实现。
///
/// - 文档正文存 `KnowledgeDocumentEntity`，按段落切块写入 `KnowledgeChunkEntity` 供本地检索；向量化后切块带 `vectorData`。
/// - 检索：可选查询向量 + 切块余弦相似度，无向量或未嵌入时回退词法打分（与 `ToolHub.search_knowledge_bag` 共用）。
/// - 后台上下文写入由 `CoreDataStack.performBackgroundTask` 统一提交，避免主线程阻塞。
final class CoreDataKnowledgeRepository: KnowledgeRepository {
    private enum Field {
        static let ownerAccountID = "ownerAccountID"
    }

    private let coreDataStack: CoreDataStack
    private let snapshotStore: SessionSnapshotStore
    private let logger: Logger

    init(
        coreDataStack: CoreDataStack,
        snapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        logger: Logger = ConsoleLogger()
    ) {
        self.coreDataStack = coreDataStack
        self.snapshotStore = snapshotStore
        self.logger = logger
    }

    func loadDocuments(matching query: String?) async throws -> [KnowledgeDocument] {
        let accountID = try await requireAccountID()
        return try await coreDataStack.performBackgroundTask { context in
            let request = KnowledgeDocumentEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            var predicates = [self.ownerPredicate(accountID)]

            if let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false {
                predicates.append(NSPredicate(
                    format: "title CONTAINS[cd] %@ OR content CONTAINS[cd] %@ OR excerpt CONTAINS[cd] %@",
                    trimmed,
                    trimmed,
                    trimmed
                ))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            return try context.fetch(request).compactMap { $0.toDomain() }
        }
    }

    func loadDocument(id: UUID) async throws -> KnowledgeDocument? {
        let accountID = try await requireAccountID()
        return try await coreDataStack.performBackgroundTask { context in
            try self.fetchDocumentEntity(id: id, ownerAccountID: accountID, context: context)?.toDomain()
        }
    }

    func createDocument(_ draft: KnowledgeDocumentDraft) async throws -> KnowledgeDocument {
        let accountID = try await requireAccountID()
        let prepared = try validate(draft)
        return try await coreDataStack.performBackgroundTask { context in
            let now = Date()
            let entity = KnowledgeDocumentEntity(context: context)
            entity.id = UUID()
            entity.ownerAccountID = accountID
            entity.createdAt = now
            entity.isEmbeddingIndexed = false
            self.apply(prepared, to: entity, updatedAt: now)
            try self.rebuildChunks(for: entity, ownerAccountID: accountID, context: context)
            guard let document = entity.toDomain() else {
                throw self.knowledgeError("知识文档创建后无法生成领域对象")
            }
            return document
        }
    }

    func updateDocument(id: UUID, draft: KnowledgeDocumentDraft) async throws -> KnowledgeDocument {
        let accountID = try await requireAccountID()
        let prepared = try validate(draft)
        return try await coreDataStack.performBackgroundTask { context in
            guard let entity = try self.fetchDocumentEntity(id: id, ownerAccountID: accountID, context: context) else {
                throw self.knowledgeError("未找到要更新的知识文档")
            }
            self.apply(prepared, to: entity, updatedAt: Date())
            try self.rebuildChunks(for: entity, ownerAccountID: accountID, context: context)
            guard let document = entity.toDomain() else {
                throw self.knowledgeError("知识文档更新后无法生成领域对象")
            }
            return document
        }
    }

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

    func deleteDocument(id: UUID) async throws {
        let accountID = try await requireAccountID()
        try await coreDataStack.performBackgroundTask { context in
            guard let entity = try self.fetchDocumentEntity(id: id, ownerAccountID: accountID, context: context) else { return }
            try self.deleteChunks(documentID: id, ownerAccountID: accountID, context: context)
            context.delete(entity)
        }
    }

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
            try self.deleteChunks(documentID: documentID, ownerAccountID: accountID, context: context)
            let now = Date()
            for (index, text) in chunkTexts.enumerated() {
                let chunk = KnowledgeChunkEntity(context: context)
                chunk.id = UUID()
                chunk.ownerAccountID = accountID
                chunk.documentID = documentID
                chunk.sequence = Int32(index)
                chunk.content = text
                chunk.vectorData = KnowledgeVectorCoding.encode(embeddings[index])
                chunk.createdAt = now
                chunk.updatedAt = now
            }
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

    func search(query: String, limit: Int, queryEmbedding: [Float]?) async throws -> [KnowledgeSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }
        let accountID = try await requireAccountID()

        return try await coreDataStack.performBackgroundTask { context in
            let documentsRequest = KnowledgeDocumentEntity.fetchRequest()
            documentsRequest.predicate = self.ownerPredicate(accountID)
            let documents = try context.fetch(documentsRequest)

            let chunkRequest = KnowledgeChunkEntity.fetchRequest()
            chunkRequest.predicate = self.ownerPredicate(accountID)
            let chunks = try context.fetch(chunkRequest)

            let lexical = self.lexicalSearchMatches(
                documents: documents,
                chunks: chunks,
                query: trimmed
            )

            let useSemantic: Bool = {
                guard let q = queryEmbedding, q.isEmpty == false else { return false }
                return chunks.contains { $0.vectorData != nil }
            }()

            if useSemantic == false {
                return self.sortedResults(from: lexical, limit: limit)
            }

            guard let qVec = queryEmbedding else {
                return self.sortedResults(from: lexical, limit: limit)
            }

            var semanticBest: [UUID: (score: Double, sequence: Int, excerpt: String, title: String)] = [:]
            for chunk in chunks {
                guard
                    let documentID = chunk.documentID,
                    let data = chunk.vectorData,
                    let content = chunk.content,
                    let vector = KnowledgeVectorCoding.decode(data),
                    vector.count == qVec.count
                else { continue }

                let sim = Double(KnowledgeEmbeddingSimilarity.cosine(qVec, vector))
                let title = documents.first(where: { $0.id == documentID })?.title ?? "Untitled"
                let excerpt = self.bestExcerpt(in: content, query: trimmed, fallback: content)
                let seq = Int(chunk.sequence)
                if let existing = semanticBest[documentID] {
                    if sim > existing.score {
                        semanticBest[documentID] = (sim, seq, excerpt, title)
                    }
                } else {
                    semanticBest[documentID] = (sim, seq, excerpt, title)
                }
            }

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

    private func lexicalSearchMatches(
        documents: [KnowledgeDocumentEntity],
        chunks: [KnowledgeChunkEntity],
        query: String
    ) -> [UUID: KnowledgeSearchResult] {
        let queryTokens = self.tokenize(query)
        var bestMatches: [UUID: KnowledgeSearchResult] = [:]

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

        for chunk in chunks {
            guard
                let documentID = chunk.documentID,
                let content = chunk.content,
                content.isEmpty == false
            else {
                continue
            }
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

    private func fetchDocumentEntity(
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

    /// 新建/更新共用：允许正文为空，与 SwiftData 版「新知识」先落库再编辑一致；空文档仍生成占位切块便于列表展示。
    /// 写作页在显式保存时再提示「正文不能为空」。
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

    private func apply(_ draft: KnowledgeDocumentDraft, to entity: KnowledgeDocumentEntity, updatedAt: Date) {
        entity.title = draft.title
        entity.content = draft.content
        entity.excerpt = makeExcerpt(from: draft.content)
        entity.scopeRaw = draft.scope.rawValue
        entity.boundModelID = draft.boundModelID
        entity.sourceRaw = draft.source.rawValue
        entity.updatedAt = updatedAt
    }

    private func rebuildChunks(
        for entity: KnowledgeDocumentEntity,
        ownerAccountID: Int64,
        context: NSManagedObjectContext
    ) throws {
        guard let documentID = entity.id, let content = entity.content else {
            throw knowledgeError("知识文档缺少必要字段，无法重建索引")
        }
        // 正文切块重建后，旧的向量索引失效。
        entity.isEmbeddingIndexed = false
        entity.lastEmbeddingModelName = nil
        try deleteChunks(documentID: documentID, ownerAccountID: ownerAccountID, context: context)
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

    private func ownerPredicate(_ accountID: Int64) -> NSPredicate {
        NSPredicate(format: "\(Field.ownerAccountID) == %lld", accountID)
    }

    private func requireAccountID() async throws -> Int64 {
        if let accountID = await snapshotStore.load()?.accountID {
            return accountID
        }
        logger.warning("知识库访问被拒绝：当前无已登录用户。", module: .general)
        throw knowledgeError("当前无登录用户，无法访问知识库数据")
    }

    private func chunkContent(_ content: String, maxLength: Int = 480) -> [String] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let paragraphs = normalized.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var buffer = ""

        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
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
            while remainder.isEmpty == false {
                let prefix = String(remainder.prefix(maxLength))
                chunks.append(prefix)
                remainder = remainder.dropFirst(prefix.count)
            }
        }

        if buffer.isEmpty == false {
            chunks.append(buffer)
        }
        return chunks.isEmpty ? [content] : chunks
    }

    private func makeExcerpt(from content: String, limit: Int = 140) -> String {
        let compact = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > limit else { return compact }
        return String(compact.prefix(limit)) + "..."
    }

    private func tokenize(_ query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
    }

    private func score(text: String, tokens: [String]) -> Double {
        guard tokens.isEmpty == false else { return 0 }
        let haystack = text.lowercased()
        return tokens.reduce(into: 0.0) { partial, token in
            if haystack.contains(token) {
                partial += 1.0 + Double(occurrences(of: token, in: haystack)) * 0.2
            }
        }
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard needle.isEmpty == false else { return 0 }
        return max(haystack.components(separatedBy: needle).count - 1, 0)
    }

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

    private func knowledgeError(_ description: String) -> NSError {
        NSError(
            domain: "SparkClient.Knowledge",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

// MARK: - Entity ↔ Domain

private extension KnowledgeDocumentEntity {
    func toDomain() -> KnowledgeDocument? {
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
            updatedAt: updatedAt
        )
    }
}
