import Foundation

/// 设备域 API。
struct SparkDeviceAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SparkNetworkEngine) {
        self.configuration = SparkBackendConfiguration(
            engine: engine,
            deviceCache: engine.cache(),
            logger: engine.networkLogger
        )
    }

    struct DeviceRegisterResult: Decodable {
        let id: Int?
        let deviceId: String
        let bundleId: String
        let created: Bool?
    }

    private struct DeviceRegistrationPayload: Encodable {
        let device_id: String
        let user_id: Int?
        let push_token: String?
        let notifications_enabled: Bool?
        let app_version: String
        let build_version: String
        let bundle_identifier: String
        let bundle_id: String
        let platform: String
        let system_version: String
        let device_model: String
        let device_model_name: String
        let device_name: String
        let screen_size: String
        let screen_scale: Double?
        let time_zone: String
        let language_code: String
        let region_code: String
        let is_simulator: Bool
    }

    /// 完整设备登记（匿名 `requiresAuth: false` 或已登录 `requiresAuth: true`）。
    ///
    /// 业务日志：`SparkBackendConfiguration.execute` 会打印「业务=…」；此处 `operation.name` 固定为 `Device.Register`，
    /// 由 `NetworkOperationBusinessPurpose` 映射为「设备域：上送安装 device_id 与全量终端画像…」。
    func registerDevice(
        bundleId: String,
        deviceId: String,
        userId: Int?,
        pushToken: String?,
        notificationsEnabled: Bool?,
        systemInfo: SparkSystemInfo,
        requiresAuth: Bool
    ) async throws -> DeviceRegisterResult {
        let payload = DeviceRegistrationPayload(
            device_id: deviceId,
            user_id: userId,
            push_token: pushToken,
            notifications_enabled: notificationsEnabled,
            app_version: systemInfo.appVersion,
            build_version: systemInfo.buildVersion,
            bundle_identifier: systemInfo.bundleIdentifier,
            bundle_id: bundleId,
            platform: systemInfo.platform,
            system_version: systemInfo.systemVersion,
            device_model: systemInfo.deviceModel,
            device_model_name: systemInfo.deviceModelName,
            device_name: systemInfo.deviceName,
            screen_size: systemInfo.screenSize,
            screen_scale: systemInfo.screenScale,
            time_zone: systemInfo.timeZone,
            language_code: systemInfo.languageCode,
            region_code: systemInfo.regionCode,
            is_simulator: systemInfo.isSimulator
        )

        let operation = CacheableSparkNetworkOperation(
            name: "Device.Register",
            apiName: "DeviceAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/device/register/",
                headers: [:],
                body: .json(AnyEncodable(payload)),
                strategy: NetworkStrategy(
                    requiresAuth: requiresAuth,
                    allowETag: false,
                    serialKey: "device.register",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(DeviceRegisterResult.self, from: response)
    }

    /// 兼容旧调用：仅 device_id / bundle_id / nickname。
    func registerTrustedDevice(
        deviceId: String,
        bundleId: String = "",
        nickname: String = ""
    ) async throws -> DeviceRegisterResult {
        let sys = SparkSystemInfo()
        return try await registerDevice(
            bundleId: bundleId.isEmpty ? sys.bundleIdentifier : bundleId,
            deviceId: deviceId,
            userId: nil,
            pushToken: nil,
            notificationsEnabled: nil,
            systemInfo: sys,
            requiresAuth: true
        )
    }
}
