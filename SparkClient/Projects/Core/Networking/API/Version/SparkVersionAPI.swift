import Foundation

struct SparkVersionAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    struct CheckResponse: Decodable, Equatable {
        let checkLogId: Int?
        let hasUpdate: Bool
        let latestVersion: String?
        let latestBuild: String?
        let forceUpdate: Bool?
        let updateTitle: String?
        let updateMessage: String?
        let downloadUrl: String?
        let releaseNotes: String?
        let message: String?
    }

    private struct ActionPayload: Encodable {
        let action: String
        let check_log_id: Int?
        let device_id: String
        let platform: String
        let bundle_id: String
    }

    struct ActionResponse: Decodable {
        let success: Bool
    }

    func checkVersion(systemInfo: SparkSystemInfo, channel: String = "production") async throws -> CheckResponse {
        let operation = CacheableSparkNetworkOperation(
            name: "Version.Check",
            apiName: "VersionAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/version/check/",
                queryItems: [
                    URLQueryItem(name: "version", value: systemInfo.appVersion),
                    URLQueryItem(name: "build", value: systemInfo.buildVersion),
                    URLQueryItem(name: "platform", value: systemInfo.platform),
                    URLQueryItem(name: "device_id", value: systemInfo.installationDeviceID),
                    URLQueryItem(name: "bundle_id", value: systemInfo.bundleIdentifier),
                    URLQueryItem(name: "channel", value: channel),
                    URLQueryItem(name: "system_version", value: systemInfo.systemVersion)
                ],
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    allowETag: false,
                    serialKey: "version.check",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .low
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(CheckResponse.self, from: response)
    }

    func recordAction(_ action: String, checkLogId: Int?, systemInfo: SparkSystemInfo) async throws -> ActionResponse {
        let payload = ActionPayload(
            action: action,
            check_log_id: checkLogId,
            device_id: systemInfo.installationDeviceID,
            platform: systemInfo.platform,
            bundle_id: systemInfo.bundleIdentifier
        )
        let operation = CacheableSparkNetworkOperation(
            name: "Version.Action",
            apiName: "VersionAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/version/action/",
                body: .json(AnyEncodable(payload)),
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    allowETag: false,
                    serialKey: "version.action",
                    retryConfig: RetryConfig(isEnabled: false, maxRetryCount: 0, retryableStatusCodes: [], retryableURLErrorCodes: [], honorsRetryAfter: false, backoffIntervals: []),
                    isIdempotent: false,
                    queuePriority: .low
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(ActionResponse.self, from: response)
    }
}
