import Foundation
import Security

/// Spark 安装级设备 ID / 设备登录密钥：与 HealthClient 共用同一 Keychain service。
///
/// Keychain：`service = com.dreamhealth.healthclient`
/// - `account = device_unique_id`：安装标识（升级前后连续）
/// - `account = device_login_secret`：设备登录高熵密钥（决策 1A）
enum SparkKeychain {
    enum DeviceCredentialError: Error {
        case deviceCredentialUnavailable
    }

    private static let service = "com.dreamhealth.healthclient"
    private static let deviceIDAccount = "device_unique_id"
    private static let deviceSecretAccount = "device_login_secret"

    static func getOrCreateDeviceID() -> String {
        if let existingID = load(account: deviceIDAccount) {
            return existingID
        }

        let newID = UUID().uuidString
        do {
            try save(newID, account: deviceIDAccount)
        } catch {
            let ns = error as NSError
            SparkLogger.log(
                level: .warning,
                module: .general,
                message: "Keychain 保存 HealthClient 兼容 device_id 失败，本次进程仍使用内存 UUID（下次冷启动会重试）。domain=\(ns.domain) code=\(ns.code)"
            )
        }
        return newID
    }

    /// 认证场景必须使用可持久化的安装标识，禁止降级为内存 UUID。
    static func getOrCreatePersistentDeviceID() throws -> String {
        if let existingID = load(account: deviceIDAccount), existingID.isEmpty == false {
            return existingID
        }
        let newID = UUID().uuidString
        do {
            try save(newID, account: deviceIDAccount)
            return newID
        } catch {
            throw DeviceCredentialError.deviceCredentialUnavailable
        }
    }

    /// 读取或创建 device_secret。保存失败不得返回仅存在于内存的临时 secret。
    static func getOrCreateDeviceSecret() throws -> String {
        if let existing = load(account: deviceSecretAccount), existing.isEmpty == false {
            return existing
        }

        let secret = try generateDeviceSecret()
        do {
            try save(secret, account: deviceSecretAccount)
        } catch {
            let ns = error as NSError
            SparkLogger.log(
                level: .error,
                module: .auth,
                message: "Keychain 保存 device_login_secret 失败，拒绝使用临时 secret。domain=\(ns.domain) code=\(ns.code)"
            )
            throw DeviceCredentialError.deviceCredentialUnavailable
        }
        SparkLogger.log(
            level: .info,
            module: .auth,
            message: "Keychain 已创建 device_login_secret（不输出明文）"
        )
        return secret
    }

    static func loadDeviceSecret() -> String? {
        load(account: deviceSecretAccount)
    }

    static func replaceDeviceSecret(_ secret: String) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw DeviceCredentialError.deviceCredentialUnavailable
        }
        try save(trimmed, account: deviceSecretAccount)
    }

    static func deleteDeviceSecret() {
        delete(account: deviceSecretAccount)
    }

    private static func generateDeviceSecret() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw DeviceCredentialError.deviceCredentialUnavailable
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
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

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
