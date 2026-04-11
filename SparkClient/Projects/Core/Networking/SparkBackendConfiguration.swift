import Foundation

/// Backend 的基础装配容器。
/// 职责类似 purchases-ios 的 `BackendConfiguration`：
/// 统一持有网络引擎、回调合并缓存和日志器，并负责执行 Operation。
final class SparkBackendConfiguration: @unchecked Sendable {
    let engine: SparkNetworkEngine
    let callbackCache: SparkCallbackCache
    let deviceCache: DeviceCache
    let logger: Logger

    init(
        engine: SparkNetworkEngine,
        deviceCache: DeviceCache = DeviceCache(),
        callbackCache: SparkCallbackCache = SparkCallbackCache(),
        logger: Logger? = nil
    ) {
        self.engine = engine
        self.deviceCache = deviceCache
        self.callbackCache = callbackCache
        self.logger = logger ?? engine.networkLogger
    }

    func execute(_ operation: some SparkNetworkOperation) async throws -> SparkNetworkResponse {
        let business = NetworkOperationBusinessPurpose.describe(operation)
        logger.debug(
            SparkNetworkingStrings.Backend.executing(
                api: operation.apiName,
                operation: operation.name,
                business: business
            ),
            module: .network
        )
        let query = operation.request.queryItems?
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&") ?? ""
        logger.debug(
            "业务=\(business) Operation 请求详情 method=\(operation.request.method.rawValue) path=\(operation.request.path) query=\(query) requiresAuth=\(operation.request.strategy.requiresAuth) allowETag=\(operation.request.strategy.allowETag) retryEnabled=\(operation.request.strategy.retryConfig.isEnabled) maxRetry=\(operation.request.strategy.retryConfig.maxRetryCount)",
            module: .network
        )

        if let key = operation.callbackCacheKey {
            return try await callbackCache.execute(
                key: key,
                operationName: operation.name,
                businessPurpose: business,
                logger: logger
            ) {
                try await operation.execute(with: self.engine)
            }
        }

        return try await operation.execute(with: engine)
    }
}
