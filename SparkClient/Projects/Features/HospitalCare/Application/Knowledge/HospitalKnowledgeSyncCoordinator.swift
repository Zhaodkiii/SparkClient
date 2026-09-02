import Foundation

// MARK: - CHAT-000055 医院知识同步 Coordinator（只读链路）
//
// Q21/Q25/Q36：
// - 每个 scope 一次 pull 事务化处理：分页全部拉齐后一次性落库；
//   中途任何一页失败，整批作废，不得只写一半。
// - cursor 失效（HOSPITAL_KNOWLEDGE_CURSOR_INVALID）：清 cursor + 清 scope 本地数据，
//   重做一次全量；仍失败保持 failed 状态，绝不复用旧 cursor 增量续跑。
// - 下一页请求绝不先于前一页确认提交（串行分页）。
// - single-flight：同 scope 并发调用合并为一次同步。

enum HospitalKnowledgeSyncError: Error, Equatable {
    case cursorInvalid
    case remoteFailed(String)
}

struct HospitalKnowledgeSyncOutcome: Equatable, Sendable {
    let scopeKey: String
    let pulledDocuments: Int
    let usedFullSnapshot: Bool
}

actor HospitalKnowledgeSyncCoordinator {
    private let remoteAPI: any HospitalCareRemoteServing
    private let repository: any HospitalKnowledgeRepository
    private var inFlight: [String: Task<HospitalKnowledgeSyncOutcome, Error>] = [:]

    init(
        remoteAPI: any HospitalCareRemoteServing,
        repository: any HospitalKnowledgeRepository
    ) {
        self.remoteAPI = remoteAPI
        self.repository = repository
    }

    /// 同步单个知识库 scope 至 manifest 声明的 revision。
    /// - Parameters:
    ///   - item: Manifest 中的 KB 条目（门禁与 revision 事实源）。
    ///   - manifestRevision: 当前会话 Manifest revision（写入同步状态）。
    ///   - forceFullSync: 显式要求首次全量（忽略本地 cursor）。
    @discardableResult
    func synchronize(
        scope: HospitalKnowledgeScope,
        item: HospitalKnowledgeManifestItem,
        manifestRevision: Int64,
        accountID: Int64,
        forceFullSync: Bool = false
    ) async throws -> HospitalKnowledgeSyncOutcome {
        let scopeKey = scope.storageKey
        if let task = inFlight[scopeKey] {
            return try await task.value
        }
        let task = Task<HospitalKnowledgeSyncOutcome, Error> {
            try await self.performSync(
                scope: scope,
                item: item,
                manifestRevision: manifestRevision,
                accountID: accountID,
                forceFullSync: forceFullSync
            )
        }
        inFlight[scopeKey] = task
        defer { inFlight.removeValue(forKey: scopeKey) }
        return try await task.value
    }

    /// Q34：按当前生效 Manifest 集合原子清理本地下线 scope。
    /// 只在所有仍生效 scope 同步成功后调用。
    func purgeStaleScopes(validItems: [HospitalKnowledgeManifestItem], accountID: Int64) {
        let validKeys = Set(validItems.map { HospitalKnowledgeScope(knowledgeBaseID: $0.knowledgeBaseID).storageKey })
        repository.purgeScopes(keeping: validKeys, accountID: accountID)
    }

    /// Q22/Q34：以 Manifest 为事实源对齐本地知识（进入医院会话后的统一入口）。
    ///
    /// - manifest 存在：逐个同步有效 scope；全部成功后把当前 agent 登记到这些 scope 的
    ///   绑定集合，并对「本地记录含当前 agent、但本次 Manifest 已不含」的 scope 做解绑清理
    ///   （绑定集合变空才物理删除，多智能体共享 KB 时互不影响）。
    /// - manifest 为 nil 且能力允许同步（无绑定）：对当前 agent 做全量解绑清理。
    /// - manifest 为 nil 且禁止同步（下架）：停止同步，保留本地缓存供历史可读。
    func reconcileWithManifest(
        _ manifest: HospitalAgentKnowledgeManifest?,
        agentID: UUID,
        capabilities: HospitalConversationCapabilities,
        accountID: Int64
    ) async {
        guard capabilities.canSyncKnowledge else { return }
        guard let manifest else {
            await unbindAllScopes(for: agentID, accountID: accountID)
            return
        }

        var syncedKeys = Set<String>()
        var allSucceeded = true
        for item in manifest.items where item.isDeleted == false {
            let scope = HospitalKnowledgeScope(knowledgeBaseID: item.knowledgeBaseID)
            do {
                try await synchronize(
                    scope: scope,
                    item: item,
                    manifestRevision: manifest.manifestRevision,
                    accountID: accountID
                )
                syncedKeys.insert(scope.storageKey)
            } catch {
                allSucceeded = false
            }
        }

        // 引用计数登记只在全部同步成功后提交，避免部分失败把有效绑定清掉。
        guard allSucceeded else { return }
        for item in manifest.items where item.isDeleted == false {
            let scope = HospitalKnowledgeScope(knowledgeBaseID: item.knowledgeBaseID)
            guard syncedKeys.contains(scope.storageKey),
                  var state = repository.syncState(for: scope, accountID: accountID) else { continue }
            var agents = state.boundAgentIDs ?? []
            agents.insert(agentID)
            state.boundAgentIDs = agents
            repository.updateSyncState(state, accountID: accountID)
        }
        await unbindScopes(for: agentID, keeping: syncedKeys, accountID: accountID)
    }

    /// 当前 agent 对所有本地 scope 解绑；绑定集合变空的 scope 物理删除。
    private func unbindAllScopes(for agentID: UUID, accountID: Int64) async {
        await unbindScopes(for: agentID, keeping: [], accountID: accountID)
    }

    private func unbindScopes(for agentID: UUID, keeping scopeKeys: Set<String>, accountID: Int64) async {
        let known = repository.knownScopes(accountID: accountID)
        for scopeKey in known where scopeKeys.contains(scopeKey) == false {
            guard let uuid = UUID(uuidString: scopeKey) else { continue }
            let scope = HospitalKnowledgeScope(knowledgeBaseID: uuid)
            guard var state = repository.syncState(for: scope, accountID: accountID) else { continue }
            var agents = state.boundAgentIDs ?? []
            guard agents.contains(agentID) else { continue }
            agents.remove(agentID)
            if agents.isEmpty {
                repository.purgeScope(scope, accountID: accountID)
            } else {
                state.boundAgentIDs = agents
                repository.updateSyncState(state, accountID: accountID)
            }
        }
    }

    // MARK: - 私有

    private func performSync(
        scope: HospitalKnowledgeScope,
        item: HospitalKnowledgeManifestItem,
        manifestRevision: Int64,
        accountID: Int64,
        forceFullSync: Bool
    ) async throws -> HospitalKnowledgeSyncOutcome {
        var state = repository.syncState(for: scope, accountID: accountID)
            ?? HospitalKnowledgeSyncState(
                scopeKey: scope.storageKey,
                lastManifestRevision: nil,
                lastRevision: nil,
                lastIndexedRevision: nil,
                cursor: nil,
                hasCompletedInitialFullSync: false,
                lastSyncAt: nil,
                lastSyncResult: nil
            )

        // 幂等：manifest 声明的 revision 与本地一致且首拉已完成 → 跳过。
        let revisionUnchanged = state.lastRevision == item.revision
            && state.lastIndexedRevision == item.indexedRevision
        if forceFullSync == false,
           state.hasCompletedInitialFullSync,
           revisionUnchanged,
           state.lastManifestRevision == manifestRevision {
            return HospitalKnowledgeSyncOutcome(scopeKey: scope.storageKey, pulledDocuments: 0, usedFullSnapshot: false)
        }

        // KB revision 变化或未完成首拉 → cursor 失效，重做全量。
        let needsFullSnapshot = forceFullSync
            || state.hasCompletedInitialFullSync == false
            || state.lastRevision != item.revision
        var cursor = needsFullSnapshot ? nil : state.cursor
        if needsFullSnapshot {
            cursor = nil
        }

        do {
            let outcome = try await pullAllPages(
                scope: scope,
                initialCursor: cursor,
                isFullSnapshot: needsFullSnapshot,
                accountID: accountID
            )
            state.lastManifestRevision = manifestRevision
            state.lastRevision = item.revision
            state.lastIndexedRevision = item.indexedRevision
            state.cursor = outcome.finalCursor
            state.hasCompletedInitialFullSync = true
            state.lastSyncAt = Date()
            state.lastSyncResult = .success
            repository.updateSyncState(state, accountID: accountID)
            return HospitalKnowledgeSyncOutcome(
                scopeKey: scope.storageKey,
                pulledDocuments: outcome.documentCount,
                usedFullSnapshot: needsFullSnapshot
            )
        } catch HospitalKnowledgeSyncError.cursorInvalid {
            // Q36：cursor 失效 → 清 cursor + 清 scope 本地数据后重做一次全量。
            repository.purgeScope(scope, accountID: accountID)
            state.cursor = nil
            state.hasCompletedInitialFullSync = false
            repository.updateSyncState(state, accountID: accountID)
            do {
                let outcome = try await pullAllPages(
                    scope: scope,
                    initialCursor: nil,
                    isFullSnapshot: true,
                    accountID: accountID
                )
                state.lastManifestRevision = manifestRevision
                state.lastRevision = item.revision
                state.lastIndexedRevision = item.indexedRevision
                state.cursor = outcome.finalCursor
                state.hasCompletedInitialFullSync = true
                state.lastSyncAt = Date()
                state.lastSyncResult = .success
                repository.updateSyncState(state, accountID: accountID)
                return HospitalKnowledgeSyncOutcome(
                    scopeKey: scope.storageKey,
                    pulledDocuments: outcome.documentCount,
                    usedFullSnapshot: true
                )
            } catch {
                state.lastSyncAt = Date()
                state.lastSyncResult = .failed
                repository.updateSyncState(state, accountID: accountID)
                throw error
            }
        } catch {
            state.lastSyncAt = Date()
            state.lastSyncResult = .failed
            repository.updateSyncState(state, accountID: accountID)
            throw error
        }
    }

    private struct PullAccumulation {
        var documents: [HospitalKnowledgeDocumentRecord] = []
        var chunks: [HospitalKnowledgeChunkRecord] = []
        var tombstonedDocumentIDs: Set<UUID> = []
        var purgedChunkDocumentIDs: Set<UUID> = []
        var finalCursor: String?
        var documentCount = 0
    }

    /// 串行分页拉齐后一次性落库（事务化：失败整批作废）。
    private func pullAllPages(
        scope: HospitalKnowledgeScope,
        initialCursor: String?,
        isFullSnapshot: Bool,
        accountID: Int64
    ) async throws -> PullAccumulation {
        var accumulation = PullAccumulation()
        var cursor = initialCursor
        var pageIndex = 0
        while true {
            let page: HospitalKnowledgePullPageDTO
            do {
                page = try await remoteAPI.pullHospitalKnowledge(
                    knowledgeBaseID: scope.knowledgeBaseID,
                    cursor: cursor,
                    limit: 100
                )
            } catch {
                if isCursorInvalid(error) {
                    throw HospitalKnowledgeSyncError.cursorInvalid
                }
                throw HospitalKnowledgeSyncError.remoteFailed(error.localizedDescription)
            }
            pageIndex += 1

            for documentDTO in page.documents {
                if documentDTO.isDeleted {
                    accumulation.tombstonedDocumentIDs.insert(documentDTO.id)
                    // tombstone 同时清理该文档本地向量。
                    accumulation.purgedChunkDocumentIDs.insert(documentDTO.id)
                    continue
                }
                accumulation.documents.append(
                    HospitalKnowledgeDocumentRecord(
                        documentID: documentDTO.id,
                        title: documentDTO.title,
                        content: documentDTO.content,
                        excerpt: documentDTO.excerpt,
                        revision: documentDTO.revision,
                        updatedAt: documentDTO.updatedAt
                    )
                )
                // 服务端只在向量新鲜时下发 chunks；revision 不一致的文档先清旧向量。
                if documentDTO.chunks.isEmpty {
                    accumulation.purgedChunkDocumentIDs.insert(documentDTO.id)
                } else {
                    accumulation.purgedChunkDocumentIDs.insert(documentDTO.id)
                    for chunkDTO in documentDTO.chunks {
                        accumulation.chunks.append(
                            HospitalKnowledgeChunkRecord(
                                chunkID: chunkDTO.id,
                                documentID: documentDTO.id,
                                sequence: chunkDTO.sequence,
                                content: chunkDTO.content,
                                contentHash: chunkDTO.contentHash,
                                documentRevision: chunkDTO.documentRevision,
                                vector: chunkDTO.vectorPayload,
                                embeddingBindingID: chunkDTO.embeddingBindingId
                            )
                        )
                    }
                }
            }

            accumulation.finalCursor = page.cursor
            accumulation.documentCount += page.documents.count
            if page.hasMore == false {
                break
            }
            cursor = page.cursor
            // 防御：服务端异常返回相同 cursor 且无数据时避免死循环。
            if page.documents.isEmpty, page.cursor == cursor, pageIndex > 1 {
                break
            }
        }

        // 事务化落库：全量快照 = 原子替换；增量 = 单次 applyDelta。
        if isFullSnapshot {
            repository.replaceScope(
                scope,
                documents: accumulation.documents,
                chunks: accumulation.chunks,
                accountID: accountID
            )
        } else {
            repository.applyDelta(
                to: scope,
                upsertedDocuments: accumulation.documents,
                tombstonedDocumentIDs: accumulation.tombstonedDocumentIDs,
                upsertedChunks: accumulation.chunks,
                purgedChunkDocumentIDs: accumulation.purgedChunkDocumentIDs,
                accountID: accountID
            )
        }
        return accumulation
    }

    private func isCursorInvalid(_ error: Error) -> Bool {
        let description = String(describing: error)
        return description.contains("HOSPITAL_KNOWLEDGE_CURSOR_INVALID")
    }
}
