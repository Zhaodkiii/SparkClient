import Foundation

/// CHAT-000057 D-011/D-012：医疗类会话「从消息列表移除」可见性偏好的账号级持久化。
///
/// 独立于 ChatThread 生命周期：不写 isDeleted，不进 HospitalConversationScopeStore；
/// 账号退出、服务端撤权、Thread 真删除时清理。
final class ConversationListVisibilityPreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var memory: [String: [String: ConversationListVisibilityPreference]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func preference(for threadID: UUID, accountID: Int64) -> ConversationListVisibilityPreference? {
        let accountKey = key(accountID)
        lock.lock()
        if let cached = memory[accountKey]?[threadID.uuidString] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        return load(accountID: accountID)[threadID.uuidString]
    }

    /// 写入/更新隐藏偏好；hidden=false 等价于恢复可见。
    func setHidden(_ hidden: Bool, threadID: UUID, accountID: Int64, now: Date = Date()) {
        var stored = load(accountID: accountID)
        if hidden {
            stored[threadID.uuidString] = ConversationListVisibilityPreference(
                threadID: threadID,
                isHidden: true,
                hiddenAt: now,
                updatedAt: now
            )
        } else {
            stored[threadID.uuidString] = nil
        }
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

    /// 登录失效/切换账号时清空全部账号的可见性偏好。
    func clearAll() {
        lock.lock()
        let keys = memory.keys.map { $0 }
        memory.removeAll()
        lock.unlock()
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    private func load(accountID: Int64) -> [String: ConversationListVisibilityPreference] {
        let accountKey = key(accountID)
        lock.lock()
        if let cached = memory[accountKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let data = defaults.data(forKey: accountKey),
              let decoded = try? JSONDecoder().decode([String: ConversationListVisibilityPreference].self, from: data)
        else {
            return [:]
        }
        lock.lock()
        memory[accountKey] = decoded
        lock.unlock()
        return decoded
    }

    private func persist(_ value: [String: ConversationListVisibilityPreference], accountID: Int64) {
        let accountKey = key(accountID)
        lock.lock()
        memory[accountKey] = value
        lock.unlock()
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: accountKey)
        }
    }

    private func key(_ accountID: Int64) -> String {
        "chat.conversation.visibility.\(accountID)"
    }
}
