import CryptoKit
import Foundation

/// 最近一次成功设备登记的持久化摘要，用于跨启动前台恢复去重（APP-STARTUP-000008）。
struct DeviceRegistrationSubmittedSnapshot: Codable, Equatable, Sendable {
    var accountID: Int?
    var isAuthenticated: Bool
    var bundleID: String
    var deviceID: String
    var countryCode: String
    var regionCode: String
    var notificationsEnabled: Bool?
    var pushTokenHash: String?
    var authorizationStatusRaw: Int?

    static func from(
        state: DeviceRegistrationState,
        authorizationStatusRaw: Int?
    ) -> DeviceRegistrationSubmittedSnapshot {
        DeviceRegistrationSubmittedSnapshot(
            accountID: state.accountID,
            isAuthenticated: state.isAuthenticated,
            bundleID: state.bundleID,
            deviceID: state.deviceID,
            countryCode: state.countryCode,
            regionCode: state.regionCode,
            notificationsEnabled: state.notificationsEnabled,
            pushTokenHash: Self.hashPushToken(state.pushToken),
            authorizationStatusRaw: authorizationStatusRaw
        )
    }

    static func hashPushToken(_ pushToken: PushTokenState) -> String? {
        guard case let .value(hex) = pushToken else { return nil }
        let digest = SHA256.hash(data: Data(hex.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

