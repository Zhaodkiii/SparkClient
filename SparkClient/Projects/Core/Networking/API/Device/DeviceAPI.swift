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
        let device_id: String
        let bundle_id: String
    }

    func registerTrustedDevice(
        deviceId: String,
        bundleId: String = "",
        nickname: String = ""
    ) async throws -> DeviceRegisterResult {
        struct Payload: Encodable {
            let device_id: String
            let bundle_id: String
            let nickname: String
        }

        let operation = CacheableSparkNetworkOperation(
            name: "Device.RegisterTrusted",
            apiName: "DeviceAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/device/register/",
                headers: [:],
                body: .json(AnyEncodable(Payload(device_id: deviceId, bundle_id: bundleId, nickname: nickname))),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "device.register",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        let result = try APIResponseDecoder.decodeWrappedData(DeviceRegisterResult.self, from: response)
        configuration.deviceCache.cache(trustedDeviceID: result.device_id)
        return result
    }
}
