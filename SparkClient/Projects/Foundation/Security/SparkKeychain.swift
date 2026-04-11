import Foundation
import Security

/// Spark 安装级设备 ID：与 HealthClient 一致，使用 Keychain 持久化 UUID（账户名与 HealthClient 区分以免同机冲突）。
///
/// HealthClient 参考：`Health/HealthClient/HealthClient/Core/Storage/Keychain.getOrCreateDeviceID()`。
enum SparkKeychain {
    private static let deviceIDAccount = "spark_client_device_unique_id"

    static func getOrCreateDeviceID() -> String {
        if let existing = load(account: deviceIDAccount) {
            return existing
        }
        let newID = UUID().uuidString
        do {
            try save(newID, account: deviceIDAccount)
        } catch {
            // 与 HealthClient 一致：写入失败仍返回内存中的 UUID，避免阻塞登录。
            // 常见原因：钥匙串权限/访问组不一致、模拟器 errSecDuplicateItem 或 -34018、
            // 真机首次解锁前访问 kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly 等。
            let ns = error as NSError
            SparkLogger.log(
                level: .warning,
                module: .general,
                message: "Keychain 保存安装级 device_id 失败，本次进程仍使用内存 UUID（下次冷启动会重试）。domain=\(ns.domain) code=\(ns.code)"
            )
        }
        return newID
    }

    private static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
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
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
