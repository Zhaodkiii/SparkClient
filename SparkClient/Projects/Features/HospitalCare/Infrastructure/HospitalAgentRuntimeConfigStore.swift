import Foundation

/// CHAT-000058：医院医生智能体专用运行配置存取（内存当前配置 + Keychain 持久化）。
///
/// 缓存键规则：`hospital-agent-runtime/{accountID}/{hospitalID}/{memberID}/{agentID}`，
/// 内容 JSON 内含 `configVersion`；UserDefaults 仅维护 key 索引（不含配置内容），
/// 用于按账号/成员/医院批量清理。
///
/// - Keychain 读取失败、解密失败、字段缺失或版本不可识别时按未命中处理；
/// - 不在任何日志中输出配置内容（endpoint / 凭证 / systemProvision）；
/// - 退出登录、切换账号、切换成员、切换医院、后台校验失效时必须调用对应清理 API。
nonisolated final class HospitalAgentRuntimeConfigStore: @unchecked Sendable {
    /// 配置定位 scope（账号 + 医院 + 成员 + 智能体）。
    struct Scope: Hashable, Sendable {
        let accountID: Int64
        let hospitalID: UUID
        let memberID: Int
        let agentID: UUID

        var storageKey: String {
            "hospital-agent-runtime/\(accountID)/\(hospitalID.uuidString.lowercased())/\(memberID)/\(agentID.uuidString.lowercased())"
        }
    }

    private let keychain: any HospitalAgentRuntimeConfigKeychainServing
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var memory: [String: HospitalAgentRuntimeConfig] = [:]
    private let indexDefaultsKey = "hospital.agent.runtime.config.keychain.index"

    init(
        keychain: any HospitalAgentRuntimeConfigKeychainServing = SecurityHospitalAgentRuntimeConfigKeychain(),
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.defaults = defaults
    }

    /// 读取缓存配置：内存 → Keychain；任何异常按未命中处理。
    func cachedConfig(for scope: Scope) -> HospitalAgentRuntimeConfig? {
        let key = scope.storageKey
        lock.lock()
        if let cached = memory[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let data = keychain.load(account: key),
              let decoded = try? JSONDecoder().decode(HospitalAgentRuntimeConfig.self, from: data)
        else {
            if keychain.load(account: key) != nil {
                // 读取成功但解码失败：按未命中处理并清除损坏条目。
                keychain.delete(account: key)
                removeFromIndex(key)
            }
            return nil
        }
        // 字段/版本校验：scope 与内容必须一致，版本必须可识别。
        guard decoded.agentID == scope.agentID,
              decoded.hospitalID == scope.hospitalID,
              decoded.memberID == scope.memberID,
              decoded.configVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            keychain.delete(account: key)
            removeFromIndex(key)
            return nil
        }
        lock.lock()
        memory[key] = decoded
        lock.unlock()
        return decoded
    }

    /// 写入/覆盖配置（内存 + Keychain + 索引）。Keychain 写入失败时保留内存副本，本次会话仍可用。
    func save(_ config: HospitalAgentRuntimeConfig, accountID: Int64) {
        let scope = Scope(
            accountID: accountID,
            hospitalID: config.hospitalID,
            memberID: config.memberID,
            agentID: config.agentID
        )
        let key = scope.storageKey
        lock.lock()
        memory[key] = config
        lock.unlock()
        guard let data = try? JSONEncoder().encode(config) else { return }
        do {
            try keychain.save(data, account: key)
            insertIntoIndex(key)
        } catch {
            // Keychain 不可用（罕见）：按“仅内存缓存”降级，不输出配置内容。
        }
    }

    /// 删除单个 scope 的配置（后台校验失效 / 服务端撤权时调用）。
    func delete(for scope: Scope) {
        let key = scope.storageKey
        lock.lock()
        memory[key] = nil
        lock.unlock()
        keychain.delete(account: key)
        removeFromIndex(key)
    }

    /// 成员切换 / 撤权：清理某账号下指定成员的全部专用配置。
    func clearMember(accountID: Int64, memberID: Int) {
        clearMatching { key in
            let parts = key.split(separator: "/")
            return parts.count == 5
                && parts[1] == Substring(String(accountID))
                && parts[3] == Substring(String(memberID))
        }
    }

    /// 医院切换：清理某账号下指定医院的全部专用配置。
    func clearHospital(accountID: Int64, hospitalID: UUID) {
        let prefix = "hospital-agent-runtime/\(accountID)/\(hospitalID.uuidString.lowercased())/"
        clearMatching { $0.hasPrefix(prefix) }
    }

    /// 切换账号 / 退出登录：清理某账号全部专用配置。
    func clearAccount(_ accountID: Int64) {
        let prefix = "hospital-agent-runtime/\(accountID)/"
        clearMatching { $0.hasPrefix(prefix) }
    }

    /// 登录失效等场景：清理全部账号的专用配置。
    func clearAll() {
        clearMatching { _ in true }
    }

    // MARK: - 内部

    private func clearMatching(_ predicate: (String) -> Bool) {
        lock.lock()
        let memoryKeys = memory.keys.filter(predicate)
        for key in memoryKeys {
            memory[key] = nil
        }
        lock.unlock()

        let indexed = loadIndex().filter(predicate)
        for key in indexed {
            keychain.delete(account: key)
        }
        if indexed.isEmpty == false {
            let remaining = loadIndex().filter { predicate($0) == false }
            persistIndex(remaining)
        }
    }

    private func loadIndex() -> [String] {
        defaults.stringArray(forKey: indexDefaultsKey) ?? []
    }

    private func persistIndex(_ keys: [String]) {
        defaults.set(keys, forKey: indexDefaultsKey)
    }

    private func insertIntoIndex(_ key: String) {
        var keys = loadIndex()
        guard keys.contains(key) == false else { return }
        keys.append(key)
        persistIndex(keys)
    }

    private func removeFromIndex(_ key: String) {
        var keys = loadIndex()
        guard keys.contains(key) else { return }
        keys.removeAll { $0 == key }
        persistIndex(keys)
    }
}

/// CHAT-000058：专用配置 Keychain 存取抽象（便于单元测试注入内存实现）。
nonisolated protocol HospitalAgentRuntimeConfigKeychainServing: Sendable {
    func save(_ data: Data, account: String) throws
    func load(account: String) -> Data?
    func delete(account: String)
}

/// 基于 Security 框架的 Keychain 实现；独立 service，不与设备凭证混用。
/// 不记录任何配置内容日志。
nonisolated struct SecurityHospitalAgentRuntimeConfigKeychain: HospitalAgentRuntimeConfigKeychainServing {
    private let service = "com.dreamhealth.sparkclient.hospital-agent-runtime"

    func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
