import Foundation

/// CHAT-000057 D-022：Thread 创建来源的账号级持久化。
///
/// 只允许已验证创建路径写入（消息页＋ → manualOrdinaryAI；医院流程 → hospitalAgentFlow）。
/// 不遍历旧 Core Data Thread 回填 provenance（D-025 不做迁移）。
final class ThreadCreationProvenanceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var memory: [String: [String: ThreadCreationProvenance]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func provenance(for threadID: UUID, accountID: Int64) -> ThreadCreationProvenance? {
        let accountKey = key(accountID)
        lock.lock()
        if let cached = memory[accountKey]?[threadID.uuidString] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        return load(accountID: accountID)[threadID.uuidString]
    }

    func remember(_ provenance: ThreadCreationProvenance, accountID: Int64) {
        var stored = load(accountID: accountID)
        stored[provenance.threadID.uuidString] = provenance
        persist(stored, accountID: accountID)
    }

    func remove(threadID: UUID, accountID: Int64) {
        var stored = load(accountID: accountID)
        stored[threadID.uuidString] = nil
        persist(stored, accountID: accountID)
    }

    func clearAccount(_ accountID: Int64) {
        let accountKey = key(accountID)
        lock.lock()
        memory[accountKey] = nil
        lock.unlock()
        defaults.removeObject(forKey: accountKey)
    }

    /// 登录失效/切换账号时清空全部账号的创建来源记录。
    func clearAll() {
        lock.lock()
        let keys = memory.keys.map { $0 }
        memory.removeAll()
        lock.unlock()
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    private func load(accountID: Int64) -> [String: ThreadCreationProvenance] {
        let accountKey = key(accountID)
        lock.lock()
        if let cached = memory[accountKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let data = defaults.data(forKey: accountKey),
              let decoded = try? JSONDecoder().decode([String: ThreadCreationProvenance].self, from: data)
        else {
            return [:]
        }
        lock.lock()
        memory[accountKey] = decoded
        lock.unlock()
        return decoded
    }

    private func persist(_ value: [String: ThreadCreationProvenance], accountID: Int64) {
        let accountKey = key(accountID)
        lock.lock()
        memory[accountKey] = value
        lock.unlock()
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: accountKey)
        }
    }

    private func key(_ accountID: Int64) -> String {
        "chat.thread.provenance.\(accountID)"
    }
}
