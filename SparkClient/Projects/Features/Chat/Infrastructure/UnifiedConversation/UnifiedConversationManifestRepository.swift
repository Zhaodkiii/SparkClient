import Foundation

/// CHAT-000057 D-020：统一消息会话 Manifest 的账号级本地仓库。
///
/// 职责：
/// - 按 accountID 命名空间持久化业务绑定（含删除墓碑）与同步 cursor；
/// - 以 threadID + bindingRevision 幂等合并 upsert/delete，旧版本不得覆盖新版本；
/// - snapshot 原子替换与 delta 增量合并共用一个持久化事务边界（先写 binding 再提交 cursor）。
final class UnifiedConversationManifestRepository: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    /// accountKey -> threadID.uuidString -> binding
    private var bindingsMemory: [String: [String: UnifiedConversationBinding]] = [:]
    /// accountKey -> syncState
    private var syncStateMemory: [String: UnifiedConversationManifestSyncState] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 查询

    func binding(for threadID: UUID, accountID: Int64) -> UnifiedConversationBinding? {
        let accountKey = bindingsKey(accountID)
        lock.lock()
        if let cached = bindingsMemory[accountKey]?[threadID.uuidString] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        return loadBindings(accountID: accountID)[threadID.uuidString]
    }

    func allBindings(accountID: Int64) -> [UnifiedConversationBinding] {
        Array(loadBindings(accountID: accountID).values)
    }

    func syncState(accountID: Int64) -> UnifiedConversationManifestSyncState {
        let accountKey = syncStateKey(accountID)
        lock.lock()
        if let cached = syncStateMemory[accountKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let data = defaults.data(forKey: accountKey),
              let decoded = try? JSONDecoder().decode(UnifiedConversationManifestSyncState.self, from: data)
        else {
            return UnifiedConversationManifestSyncState(accountID: accountID)
        }
        lock.lock()
        syncStateMemory[accountKey] = decoded
        lock.unlock()
        return decoded
    }

    /// Manifest 是否已为该账号完成过至少一次成功同步（决定 unknown 门控是否生效）。
    func hasCompletedInitialSync(accountID: Int64) -> Bool {
        syncState(accountID: accountID).lastSuccessfulSyncAt != nil
    }

    // MARK: - delta 增量合并（revision 幂等）

    /// 应用一批增量变更；仅当所有变更合并成功后由调用方提交 cursor。
    /// - Returns: 实际发生变化（upsert/delete 生效）的 threadID 集合。
    @discardableResult
    func applyDeltaChanges(
        _ changes: [UnifiedConversationBinding],
        accountID: Int64
    ) -> Set<UUID> {
        var stored = loadBindings(accountID: accountID)
        var changed: Set<UUID> = []
        for change in changes {
            let key = change.threadID.uuidString
            let currentRevision = stored[key]?.bindingRevision ?? -1
            guard currentRevision < change.bindingRevision else { continue }
            stored[key] = change
            changed.insert(change.threadID)
        }
        persistBindings(stored, accountID: accountID)
        return changed
    }

    // MARK: - snapshot 原子替换

    /// 全量重建：以快照内容整体替换该账号绑定集合（快照已包含 delete/revoke 收缩结果）。
    func replaceBindingsSnapshot(
        _ bindings: [UnifiedConversationBinding],
        accountID: Int64
    ) {
        var mapped: [String: UnifiedConversationBinding] = [:]
        for binding in bindings {
            mapped[binding.threadID.uuidString] = binding
        }
        persistBindings(mapped, accountID: accountID)
    }

    // MARK: - cursor / syncState

    func saveSyncState(_ state: UnifiedConversationManifestSyncState) {
        let accountKey = syncStateKey(state.accountID)
        lock.lock()
        syncStateMemory[accountKey] = state
        lock.unlock()
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: accountKey)
        }
    }

    // MARK: - 定向清理

    func removeBinding(threadID: UUID, accountID: Int64) {
        var stored = loadBindings(accountID: accountID)
        stored[threadID.uuidString] = nil
        persistBindings(stored, accountID: accountID)
    }

    func clearAccount(_ accountID: Int64) {
        let bindingsAccountKey = bindingsKey(accountID)
        let syncAccountKey = syncStateKey(accountID)
        lock.lock()
        bindingsMemory[bindingsAccountKey] = nil
        syncStateMemory[syncAccountKey] = nil
        lock.unlock()
        defaults.removeObject(forKey: bindingsAccountKey)
        defaults.removeObject(forKey: syncAccountKey)
    }

    /// 登录失效/切换账号时清空全部账号的 Manifest 缓存。
    func clearAll() {
        lock.lock()
        let bindingKeys = bindingsMemory.keys.map { $0 }
        let syncKeys = syncStateMemory.keys.map { $0 }
        bindingsMemory.removeAll()
        syncStateMemory.removeAll()
        lock.unlock()
        for key in bindingKeys + syncKeys {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - 私有

    private func loadBindings(accountID: Int64) -> [String: UnifiedConversationBinding] {
        let accountKey = bindingsKey(accountID)
        lock.lock()
        if let cached = bindingsMemory[accountKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let data = defaults.data(forKey: accountKey),
              let decoded = try? JSONDecoder().decode([String: UnifiedConversationBinding].self, from: data)
        else {
            return [:]
        }
        lock.lock()
        bindingsMemory[accountKey] = decoded
        lock.unlock()
        return decoded
    }

    private func persistBindings(_ value: [String: UnifiedConversationBinding], accountID: Int64) {
        let accountKey = bindingsKey(accountID)
        lock.lock()
        bindingsMemory[accountKey] = value
        lock.unlock()
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: accountKey)
        }
    }

    private func bindingsKey(_ accountID: Int64) -> String {
        "chat.unified.manifest.bindings.\(accountID)"
    }

    private func syncStateKey(_ accountID: Int64) -> String {
        "chat.unified.manifest.syncstate.\(accountID)"
    }
}
