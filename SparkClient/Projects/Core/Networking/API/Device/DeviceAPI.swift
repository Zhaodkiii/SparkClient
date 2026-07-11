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

    nonisolated private struct DeviceRegistrationPayload: Encodable {
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
        let country_code: String
        let is_simulator: Bool
    }

    /// 完整设备登记（匿名 `requiresAuth: false` 或已登录 `requiresAuth: true`）。
    ///
    /// `push_token`：`nil` 省略表示不覆盖服务端旧 token；`""` 表示清空；非空字符串为当前 token。
    ///
    /// 业务日志：`SparkBackendConfiguration.execute` 会打印「业务=…」；此处 `operation.name` 固定为 `Device.Register`，
    /// 由 `NetworkOperationBusinessPurpose` 映射为「设备域：上送安装 device_id 与全量终端画像…」。
    func registerDevice(
        state: DeviceRegistrationState,
        pushToken: String?,
        requiresAuth: Bool
    ) async throws -> DeviceRegisterResult {
        let payload = DeviceRegistrationPayload(
            device_id: state.deviceID,
            user_id: state.accountID,
            push_token: pushToken,
            notifications_enabled: state.notificationsEnabled,
            app_version: state.appVersion,
            build_version: state.buildVersion,
            bundle_identifier: state.bundleID,
            bundle_id: state.bundleID,
            platform: state.platform,
            system_version: state.systemVersion,
            device_model: state.deviceModel,
            device_model_name: state.deviceModelName,
            device_name: state.deviceName,
            screen_size: state.screenSize,
            screen_scale: state.screenScale,
            time_zone: state.timeZone,
            language_code: state.languageCode,
            region_code: state.regionCode,
            country_code: state.countryCode,
            is_simulator: state.isSimulator
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
}
