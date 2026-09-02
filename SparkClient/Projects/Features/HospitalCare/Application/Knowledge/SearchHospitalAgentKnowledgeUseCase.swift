import Foundation

// MARK: - CHAT-000055 医院知识检索（Q32/Q33）
//
// 向量有效性门禁（双重校验）：
// 1. KB 级：Manifest item.isVectorFresh（vectorStatus == current 且 indexedRevision == revision）。
// 2. 文档级：参与召回的 chunk.documentRevision == 当前正文 revision。
// 任一不满足 → 降级关键词全文检索，结果必须带回明确模式与原因。
// 空查询 → metadataOnly（只按元数据返回最新条目，不做内容打分）。

struct SearchHospitalAgentKnowledgeUseCase: Sendable {
    let repository: any HospitalKnowledgeRepository

    init(repository: any HospitalKnowledgeRepository) {
        self.repository = repository
    }

    struct Input: Sendable {
        let scope: HospitalKnowledgeScope
        let accountID: Int64
        let query: String
        let manifestItem: HospitalKnowledgeManifestItem?
        /// 可选的查询向量（Demo 端暂无本地 embedding 能力；注入后才可能走向量召回）。
        let queryEmbedding: [Float]?
        let limit: Int

        init(
            scope: HospitalKnowledgeScope,
            accountID: Int64,
            query: String,
            manifestItem: HospitalKnowledgeManifestItem?,
            queryEmbedding: [Float]? = nil,
            limit: Int = 5
        ) {
            self.scope = scope
            self.accountID = accountID
            self.query = query
            self.manifestItem = manifestItem
            self.queryEmbedding = queryEmbedding
            self.limit = limit
        }
    }

    func execute(_ input: Input) -> HospitalKnowledgeSearchResult {
        let documents = repository.documents(in: input.scope, accountID: input.accountID)
        let trimmedQuery = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let latestRevision = input.manifestItem?.revision

        // 空查询：只按元数据返回，不做内容召回。
        if trimmedQuery.isEmpty {
            let hits = documents
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                .prefix(input.limit)
                .map { document in
                    HospitalKnowledgeSearchHit(
                        documentID: document.documentID,
                        title: document.title,
                        snippet: document.excerpt.isEmpty ? String(document.content.prefix(80)) : document.excerpt,
                        score: 0,
                        documentRevision: document.revision,
                        isStaleContent: latestRevision.map { document.revision > $0 } ?? false
                    )
                }
            return HospitalKnowledgeSearchResult(mode: .metadataOnly, hits: Array(hits), fallbackReason: nil)
        }

        // 向量路径：门禁全过且注入了查询向量才执行。
        if let manifestItem = input.manifestItem,
           manifestItem.isVectorFresh,
           let queryEmbedding = input.queryEmbedding,
           queryEmbedding.isEmpty == false {
            let vectorResult = vectorSearch(input: input, documents: documents, queryEmbedding: queryEmbedding)
            if vectorResult.hits.isEmpty == false {
                return vectorResult
            }
            // 向量无命中：继续走关键词兜底，保证召回闭环。
        }

        return keywordSearch(input: input, documents: documents, query: trimmedQuery)
    }

    // MARK: - 向量召回（Q33 文档级门禁）

    private func vectorSearch(
        input: Input,
        documents: [HospitalKnowledgeDocumentRecord],
        queryEmbedding: [Float]
    ) -> HospitalKnowledgeSearchResult {
        let documentMap = Dictionary(uniqueKeysWithValues: documents.map { ($0.documentID, $0) })
        let chunks = repository.chunks(in: input.scope, accountID: input.accountID)
        var bestByDocument: [UUID: (score: Double, chunk: HospitalKnowledgeChunkRecord)] = [:]

        for chunk in chunks {
            guard let document = documentMap[chunk.documentID] else { continue }
            // 文档级门禁：旧 revision 向量不得冒充新正文向量。
            guard chunk.documentRevision == document.revision else { continue }
            guard chunk.vector.count == queryEmbedding.count, chunk.vector.isEmpty == false else { continue }
            let score = cosineSimilarity(queryEmbedding, chunk.vector)
            if let existing = bestByDocument[chunk.documentID], existing.score >= score {
                continue
            }
            bestByDocument[chunk.documentID] = (score, chunk)
        }

        let hits = bestByDocument
            .sorted { $0.value.score > $1.value.score }
            .prefix(input.limit)
            .compactMap { documentID, entry -> HospitalKnowledgeSearchHit? in
                guard let document = documentMap[documentID] else { return nil }
                return HospitalKnowledgeSearchHit(
                    documentID: documentID,
                    title: document.title,
                    snippet: entry.chunk.content,
                    score: entry.score,
                    documentRevision: document.revision,
                    isStaleContent: false
                )
            }
        return HospitalKnowledgeSearchResult(mode: .vector, hits: Array(hits), fallbackReason: nil)
    }

    // MARK: - 关键词降级召回

    private func keywordSearch(
        input: Input,
        documents: [HospitalKnowledgeDocumentRecord],
        query: String
    ) -> HospitalKnowledgeSearchResult {
        let terms = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
        let keywords = terms.isEmpty ? [query] : terms
        let latestRevision = input.manifestItem?.revision

        let hits: [HospitalKnowledgeSearchHit] = documents.compactMap { document in
            let title = document.title.lowercased()
            let content = document.content.lowercased()
            var score = 0.0
            var matched = false
            for keyword in keywords {
                let term = keyword.lowercased()
                if title.contains(term) {
                    score += 3.0
                    matched = true
                }
                let occurrences = content.components(separatedBy: term).count - 1
                if occurrences > 0 {
                    score += Double(min(occurrences, 5))
                    matched = true
                }
            }
            guard matched else { return nil }
            return HospitalKnowledgeSearchHit(
                documentID: document.documentID,
                title: document.title,
                snippet: snippet(for: document.content, keywords: keywords),
                score: score,
                documentRevision: document.revision,
                isStaleContent: latestRevision.map { document.revision > $0 } ?? false
            )
        }
        .sorted { $0.score > $1.score }
        .prefix(input.limit)
        .map { $0 }

        let reason: String?
        if let item = input.manifestItem, item.isVectorFresh == false {
            reason = "vector_not_fresh:\(item.vectorStatus.rawValue)"
        } else if input.queryEmbedding == nil {
            reason = "query_embedding_unavailable"
        } else {
            reason = nil
        }
        return HospitalKnowledgeSearchResult(mode: .keywordFallback, hits: hits, fallbackReason: reason)
    }

    private func snippet(for content: String, keywords: [String]) -> String {
        let lowered = content.lowercased()
        for keyword in keywords {
            if let range = lowered.range(of: keyword.lowercased()) {
                let start = content.index(range.lowerBound, offsetBy: -30, limitedBy: content.startIndex) ?? content.startIndex
                let end = content.index(range.upperBound, offsetBy: 60, limitedBy: content.endIndex) ?? content.endIndex
                return String(content[start..<end])
            }
        }
        return String(content.prefix(80))
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        var dot = 0.0
        var lhsNorm = 0.0
        var rhsNorm = 0.0
        for index in lhs.indices {
            dot += Double(lhs[index] * rhs[index])
            lhsNorm += Double(lhs[index] * lhs[index])
            rhsNorm += Double(rhs[index] * rhs[index])
        }
        guard lhsNorm > 0, rhsNorm > 0 else { return 0 }
        return dot / (lhsNorm.squareRoot() * rhsNorm.squareRoot())
    }
}
