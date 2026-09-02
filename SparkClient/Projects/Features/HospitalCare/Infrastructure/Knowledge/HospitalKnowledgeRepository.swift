import Foundation

// MARK: - CHAT-000055 医院知识只读仓库
//
// 本地知识按「医院科普知识库 scope」存储（Q26），不做按智能体维度的拷贝；
// 与个人知识库存储完全分离（独立 UserDefaults suite 前缀）。
// 所有变更操作原子生效：读取方要么看到变更前、要么看到变更后（Q21/Q36）。

nonisolated protocol HospitalKnowledgeRepository: AnyObject, Sendable {
    /// 读取某 scope 的同步状态；未同步过返回 nil。
    func syncState(for scope: HospitalKnowledgeScope, accountID: Int64) -> HospitalKnowledgeSyncState?
    /// 覆盖写入同步状态。
    func updateSyncState(_ state: HospitalKnowledgeSyncState, accountID: Int64)

    /// 首次全量 / 清空重建：原子替换整个 scope 的正文与向量。
    func replaceScope(
        _ scope: HospitalKnowledgeScope,
        documents: [HospitalKnowledgeDocumentRecord],
        chunks: [HospitalKnowledgeChunkRecord],
        accountID: Int64
    )
    /// 增量事务：upsert 正文/向量 + 删除 tombstone；一次调用内全部生效或全部不生效。
    func applyDelta(
        to scope: HospitalKnowledgeScope,
        upsertedDocuments: [HospitalKnowledgeDocumentRecord],
        tombstonedDocumentIDs: Set<UUID>,
        upsertedChunks: [HospitalKnowledgeChunkRecord],
        purgedChunkDocumentIDs: Set<UUID>,
        accountID: Int64
    )
    /// Q34：原子清理 scope（解绑/删除后本地必须完全清除）。
    func purgeScope(_ scope: HospitalKnowledgeScope, accountID: Int64)
    /// Q34：批量原子清理；keeping 之外的本地 scope 全部清除。
    func purgeScopes(keeping scopeKeys: Set<String>, accountID: Int64)

    func documents(in scope: HospitalKnowledgeScope, accountID: Int64) -> [HospitalKnowledgeDocumentRecord]
    func chunks(in scope: HospitalKnowledgeScope, accountID: Int64) -> [HospitalKnowledgeChunkRecord]
    /// 当前账号本地已有的全部 scope。
    func knownScopes(accountID: Int64) -> Set<String>
    /// 退出登录/账号切换时清空内存态。
    func resetInMemoryState()
}

// MARK: - UserDefaults 实现（Demo 数据量级，JSON 整体持久化 + 内存缓存）

nonisolated final class HospitalKnowledgeUserDefaultsRepository: HospitalKnowledgeRepository, @unchecked Sendable {
    private struct Snapshot: Codable {
        var syncStates: [String: HospitalKnowledgeSyncState] = [:]
        var documents: [String: [String: HospitalKnowledgeDocumentRecord]] = [:]
        var chunks: [String: [String: HospitalKnowledgeChunkRecord]] = [:]
    }

    private let lock = NSRecursiveLock()
    private let defaults: UserDefaults
    private let storageKeyPrefix: String
    /// accountID -> Snapshot
    private var cache: [Int64: Snapshot] = [:]

    init(
        defaults: UserDefaults = .standard,
        storageKeyPrefix: String = "hospital_care.knowledge.store.v1"
    ) {
        self.defaults = defaults
        self.storageKeyPrefix = storageKeyPrefix
    }

    func syncState(for scope: HospitalKnowledgeScope, accountID: Int64) -> HospitalKnowledgeSyncState? {
        locked { snapshot(for: accountID).syncStates[scope.storageKey] }
    }

    func updateSyncState(_ state: HospitalKnowledgeSyncState, accountID: Int64) {
        locked {
            var snapshot = snapshot(for: accountID)
            snapshot.syncStates[state.scopeKey] = state
            save(snapshot, accountID: accountID)
        }
    }

    func replaceScope(
        _ scope: HospitalKnowledgeScope,
        documents: [HospitalKnowledgeDocumentRecord],
        chunks: [HospitalKnowledgeChunkRecord],
        accountID: Int64
    ) {
        locked {
            var snapshot = snapshot(for: accountID)
            snapshot.documents[scope.storageKey] = Dictionary(
                uniqueKeysWithValues: documents.map { ($0.documentID.uuidString, $0) }
            )
            snapshot.chunks[scope.storageKey] = Dictionary(
                uniqueKeysWithValues: chunks.map { ($0.chunkID.uuidString, $0) }
            )
            save(snapshot, accountID: accountID)
        }
    }

    func applyDelta(
        to scope: HospitalKnowledgeScope,
        upsertedDocuments: [HospitalKnowledgeDocumentRecord],
        tombstonedDocumentIDs: Set<UUID>,
        upsertedChunks: [HospitalKnowledgeChunkRecord],
        purgedChunkDocumentIDs: Set<UUID>,
        accountID: Int64
    ) {
        locked {
            var snapshot = snapshot(for: accountID)
            var documents = snapshot.documents[scope.storageKey] ?? [:]
            var chunks = snapshot.chunks[scope.storageKey] ?? [:]

            for document in upsertedDocuments {
                documents[document.documentID.uuidString] = document
            }
            for documentID in tombstonedDocumentIDs {
                documents.removeValue(forKey: documentID.uuidString)
            }
            let purgedDocumentIDs = purgedChunkDocumentIDs.union(tombstonedDocumentIDs)
            if purgedDocumentIDs.isEmpty == false {
                chunks = chunks.filter { _, chunk in
                    purgedDocumentIDs.contains(chunk.documentID) == false
                }
            }
            for chunk in upsertedChunks {
                chunks[chunk.chunkID.uuidString] = chunk
            }

            snapshot.documents[scope.storageKey] = documents
            snapshot.chunks[scope.storageKey] = chunks
            save(snapshot, accountID: accountID)
        }
    }

    func purgeScope(_ scope: HospitalKnowledgeScope, accountID: Int64) {
        locked {
            var snapshot = snapshot(for: accountID)
            snapshot.documents.removeValue(forKey: scope.storageKey)
            snapshot.chunks.removeValue(forKey: scope.storageKey)
            snapshot.syncStates.removeValue(forKey: scope.storageKey)
            save(snapshot, accountID: accountID)
        }
    }

    func purgeScopes(keeping scopeKeys: Set<String>, accountID: Int64) {
        locked {
            var snapshot = snapshot(for: accountID)
            snapshot.documents = snapshot.documents.filter { scopeKeys.contains($0.key) }
            snapshot.chunks = snapshot.chunks.filter { scopeKeys.contains($0.key) }
            snapshot.syncStates = snapshot.syncStates.filter { scopeKeys.contains($0.key) }
            save(snapshot, accountID: accountID)
        }
    }

    func documents(in scope: HospitalKnowledgeScope, accountID: Int64) -> [HospitalKnowledgeDocumentRecord] {
        locked {
            Array(snapshot(for: accountID).documents[scope.storageKey]?.values ?? [:].values)
        }
    }

    func chunks(in scope: HospitalKnowledgeScope, accountID: Int64) -> [HospitalKnowledgeChunkRecord] {
        locked {
            Array(snapshot(for: accountID).chunks[scope.storageKey]?.values ?? [:].values)
        }
    }

    func knownScopes(accountID: Int64) -> Set<String> {
        locked {
            let snapshot = snapshot(for: accountID)
            return Set(snapshot.documents.keys).union(snapshot.syncStates.keys)
        }
    }

    func resetInMemoryState() {
        locked { cache.removeAll() }
    }

    // MARK: - 私有

    private func snapshot(for accountID: Int64) -> Snapshot {
        if let cached = cache[accountID] { return cached }
        let key = storageKey(for: accountID)
        let decoded: Snapshot
        if let data = defaults.data(forKey: key),
           let value = try? JSONDecoder().decode(Snapshot.self, from: data) {
            decoded = value
        } else {
            decoded = Snapshot()
        }
        cache[accountID] = decoded
        return decoded
    }

    private func save(_ snapshot: Snapshot, accountID: Int64) {
        cache[accountID] = snapshot
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey(for: accountID))
    }

    private func storageKey(for accountID: Int64) -> String {
        "\(storageKeyPrefix).account.\(accountID)"
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

// MARK: - 内存实现（测试 / 预览用）

nonisolated final class HospitalKnowledgeInMemoryRepository: HospitalKnowledgeRepository, @unchecked Sendable {
    private struct Snapshot {
        var syncStates: [String: HospitalKnowledgeSyncState] = [:]
        var documents: [String: [String: HospitalKnowledgeDocumentRecord]] = [:]
        var chunks: [String: [String: HospitalKnowledgeChunkRecord]] = [:]
    }

    private let lock = NSRecursiveLock()
    private var cache: [Int64: Snapshot] = [:]

    init() {}

    func syncState(for scope: HospitalKnowledgeScope, accountID: Int64) -> HospitalKnowledgeSyncState? {
        locked { cache[accountID]?.syncStates[scope.storageKey] }
    }

    func updateSyncState(_ state: HospitalKnowledgeSyncState, accountID: Int64) {
        locked {
            var snapshot = cache[accountID] ?? Snapshot()
            snapshot.syncStates[state.scopeKey] = state
            cache[accountID] = snapshot
        }
    }

    func replaceScope(
        _ scope: HospitalKnowledgeScope,
        documents: [HospitalKnowledgeDocumentRecord],
        chunks: [HospitalKnowledgeChunkRecord],
        accountID: Int64
    ) {
        locked {
            var snapshot = cache[accountID] ?? Snapshot()
            snapshot.documents[scope.storageKey] = Dictionary(
                uniqueKeysWithValues: documents.map { ($0.documentID.uuidString, $0) }
            )
            snapshot.chunks[scope.storageKey] = Dictionary(
                uniqueKeysWithValues: chunks.map { ($0.chunkID.uuidString, $0) }
            )
            cache[accountID] = snapshot
        }
    }

    func applyDelta(
        to scope: HospitalKnowledgeScope,
        upsertedDocuments: [HospitalKnowledgeDocumentRecord],
        tombstonedDocumentIDs: Set<UUID>,
        upsertedChunks: [HospitalKnowledgeChunkRecord],
        purgedChunkDocumentIDs: Set<UUID>,
        accountID: Int64
    ) {
        locked {
            var snapshot = cache[accountID] ?? Snapshot()
            var documents = snapshot.documents[scope.storageKey] ?? [:]
            var chunks = snapshot.chunks[scope.storageKey] ?? [:]
            for document in upsertedDocuments {
                documents[document.documentID.uuidString] = document
            }
            for documentID in tombstonedDocumentIDs {
                documents.removeValue(forKey: documentID.uuidString)
            }
            let purgedDocumentIDs = purgedChunkDocumentIDs.union(tombstonedDocumentIDs)
            if purgedDocumentIDs.isEmpty == false {
                chunks = chunks.filter { _, chunk in purgedDocumentIDs.contains(chunk.documentID) == false }
            }
            for chunk in upsertedChunks {
                chunks[chunk.chunkID.uuidString] = chunk
            }
            snapshot.documents[scope.storageKey] = documents
            snapshot.chunks[scope.storageKey] = chunks
            cache[accountID] = snapshot
        }
    }

    func purgeScope(_ scope: HospitalKnowledgeScope, accountID: Int64) {
        locked {
            var snapshot = cache[accountID] ?? Snapshot()
            snapshot.documents.removeValue(forKey: scope.storageKey)
            snapshot.chunks.removeValue(forKey: scope.storageKey)
            snapshot.syncStates.removeValue(forKey: scope.storageKey)
            cache[accountID] = snapshot
        }
    }

    func purgeScopes(keeping scopeKeys: Set<String>, accountID: Int64) {
        locked {
            var snapshot = cache[accountID] ?? Snapshot()
            snapshot.documents = snapshot.documents.filter { scopeKeys.contains($0.key) }
            snapshot.chunks = snapshot.chunks.filter { scopeKeys.contains($0.key) }
            snapshot.syncStates = snapshot.syncStates.filter { scopeKeys.contains($0.key) }
            cache[accountID] = snapshot
        }
    }

    func documents(in scope: HospitalKnowledgeScope, accountID: Int64) -> [HospitalKnowledgeDocumentRecord] {
        locked { Array(cache[accountID]?.documents[scope.storageKey]?.values ?? [:].values) }
    }

    func chunks(in scope: HospitalKnowledgeScope, accountID: Int64) -> [HospitalKnowledgeChunkRecord] {
        locked { Array(cache[accountID]?.chunks[scope.storageKey]?.values ?? [:].values) }
    }

    func knownScopes(accountID: Int64) -> Set<String> {
        locked {
            let snapshot = cache[accountID] ?? Snapshot()
            return Set(snapshot.documents.keys).union(snapshot.syncStates.keys)
        }
    }

    func resetInMemoryState() {
        locked { cache.removeAll() }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
