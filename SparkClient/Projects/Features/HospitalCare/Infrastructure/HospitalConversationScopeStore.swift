import Foundation

struct HospitalConversationScope: Codable, Equatable, Sendable {
    let threadID: UUID
    let agentID: UUID
    let memberID: Int
    let hospitalID: UUID
}

/// 记录医院会话 `threadID -> agentID/memberID`，供跳过通用引导卡和会话内新建继承智能体。
final class HospitalConversationScopeStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var memory: [String: [String: HospitalConversationScope]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func scope(for threadID: UUID, accountID: Int64) -> HospitalConversationScope? {
        let accountKey = key(accountID)
        lock.lock()
        if let cached = memory[accountKey]?[threadID.uuidString] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let stored = load(accountID: accountID)
        return stored[threadID.uuidString]
    }

    func remember(_ scope: HospitalConversationScope, accountID: Int64) {
        var stored = load(accountID: accountID)
        stored[scope.threadID.uuidString] = scope
        persist(stored, accountID: accountID)
    }

    func clearAccount(_ accountID: Int64) {
        let accountKey = key(accountID)
        lock.lock()
        memory[accountKey] = nil
        lock.unlock()
        defaults.removeObject(forKey: accountKey)
    }

    /// 登录失效/切换账号时清空全部账号的 scope 记忆（CHAT-000054）。
    func clearAll() {
        lock.lock()
        let keys = memory.keys.map { $0 }
        memory.removeAll()
        lock.unlock()
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    private func load(accountID: Int64) -> [String: HospitalConversationScope] {
        let accountKey = key(accountID)
        lock.lock()
        if let cached = memory[accountKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let data = defaults.data(forKey: accountKey),
              let decoded = try? JSONDecoder().decode([String: HospitalConversationScope].self, from: data)
        else {
            return [:]
        }
        lock.lock()
        memory[accountKey] = decoded
        lock.unlock()
        return decoded
    }

    private func persist(_ value: [String: HospitalConversationScope], accountID: Int64) {
        let accountKey = key(accountID)
        lock.lock()
        memory[accountKey] = value
        lock.unlock()
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: accountKey)
        }
    }

    private func key(_ accountID: Int64) -> String {
        "hospital.conversation.scope.\(accountID)"
    }
}
