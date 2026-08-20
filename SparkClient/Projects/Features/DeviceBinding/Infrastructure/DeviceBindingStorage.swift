import Foundation

/// 设备绑定信息本地持久化（UserDefaults 存储，按当前登录账号隔离）。
///
/// 参考项目已有策略（`PendingMemberInviteStore` / `UserDefaultsSelectedMemberIDStore`）：
/// 键为 `前缀 + 账号 ID`，绑定数据随账号隔离，账号登出/卸载后不会误读到其他账号的绑定。
final class DeviceBindingStorage: @unchecked Sendable {
    static let shared = DeviceBindingStorage()

    private let defaults: UserDefaults
    private let keyPrefix = "deviceBinding.bindings.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 读取指定账号的全部绑定记录。
    func loadBindings(accountID: Int64) -> [DeviceBinding] {
        guard let data = defaults.data(forKey: key(accountID: accountID)) else { return [] }
        return (try? JSONDecoder().decode([DeviceBinding].self, from: data)) ?? []
    }

    /// 持久化指定账号的全部绑定记录。
    func saveBindings(_ bindings: [DeviceBinding], accountID: Int64) throws {
        let data = try JSONEncoder().encode(bindings)
        defaults.set(data, forKey: key(accountID: accountID))
    }

    /// 清理指定账号的绑定记录。
    func clear(accountID: Int64) {
        defaults.removeObject(forKey: key(accountID: accountID))
    }

    // MARK: - Private

    private func key(accountID: Int64) -> String {
        keyPrefix + String(accountID)
    }
}