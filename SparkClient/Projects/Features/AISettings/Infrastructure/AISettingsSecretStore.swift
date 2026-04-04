import Foundation
import Security

protocol AISettingsSecretStore: Sendable {
    func read(account: String) -> String?
    func write(_ value: String, account: String)
    func delete(account: String)
}

struct KeychainAISettingsSecretStore: AISettingsSecretStore {
    private let service: String

    init(service: String = "com.sparkclient.ai.settings.secrets.v1") {
        self.service = service
    }

    func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
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

struct InMemoryAISettingsSecretStore: AISettingsSecretStore {
    private let storage: Atomic<[String: String]>

    init(seed: [String: String] = [:]) {
        self.storage = Atomic(seed)
    }

    func read(account: String) -> String? {
        storage.value[account]
    }

    func write(_ value: String, account: String) {
        var next = storage.value
        next[account] = value
        storage.value = next
    }

    func delete(account: String) {
        var next = storage.value
        next.removeValue(forKey: account)
        storage.value = next
    }

    func dump() -> [String: String] {
        storage.value
    }
}
