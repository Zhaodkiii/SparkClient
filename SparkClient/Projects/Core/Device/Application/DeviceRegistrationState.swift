import Foundation

/// `push_token` 字段语义：未知不覆盖服务端、空字符串清空、有值则更新。
enum PushTokenState: Equatable, Sendable {
    /// 本次未知 token，请求体省略 `push_token`。
    case unknown
    /// 明确清空服务端 token（`push_token=""`）。
    case cleared
    case value(String)
}

/// 设备登记待提交/已提交的统一状态（与 `/api/v1/device/register/` 对齐）。
struct DeviceRegistrationState: Equatable, Sendable {
    var accountID: Int?
    var isAuthenticated: Bool
    var bundleID: String
    var deviceID: String
    var appVersion: String
    var buildVersion: String
    var platform: String
    var systemVersion: String
    var deviceModel: String
    var deviceModelName: String
    var deviceName: String
    var screenSize: String
    var screenScale: Double?
    var timeZone: String
    var languageCode: String
    var regionCode: String
    var countryCode: String
    var isSimulator: Bool
    var notificationsEnabled: Bool?
    var pushToken: PushTokenState

    static func baseSnapshot(
        accountID: Int?,
        systemInfo: SparkSystemInfo
    ) -> DeviceRegistrationState {
        DeviceRegistrationState(
            accountID: accountID,
            isAuthenticated: accountID != nil,
            bundleID: systemInfo.bundleIdentifier,
            deviceID: systemInfo.installationDeviceID,
            appVersion: systemInfo.appVersion,
            buildVersion: systemInfo.buildVersion,
            platform: systemInfo.platform,
            systemVersion: systemInfo.systemVersion,
            deviceModel: systemInfo.deviceModel,
            deviceModelName: systemInfo.deviceModelName,
            deviceName: systemInfo.deviceName,
            screenSize: systemInfo.screenSize,
            screenScale: systemInfo.screenScale,
            timeZone: systemInfo.timeZone,
            languageCode: systemInfo.languageCode,
            regionCode: systemInfo.regionCode,
            countryCode: systemInfo.mostLikelyCountryCode,
            isSimulator: systemInfo.isSimulator,
            notificationsEnabled: nil,
            pushToken: .unknown
        )
    }
}
