import Foundation

/// 同类请求回调合并缓存。
/// 当多个调用方并发请求相同资源时，只执行一次真实网络请求，
/// 其余调用方直接等待同一个 `Task` 结果。
actor SparkCallbackCache {
    private var inFlight: [String: Task<SparkNetworkResponse, Error>] = [:]

    func execute(
        key: String,
        operationName: String,
        businessPurpose: String,
        logger: Logger,
        taskFactory: @escaping @Sendable () async throws -> SparkNetworkResponse
    ) async throws -> SparkNetworkResponse {
        if let existing = inFlight[key] {
            logger.debug(
                SparkNetworkingStrings.Backend.callbackCacheHit(
                    key: key,
                    operation: operationName,
                    business: businessPurpose
                ),
                module: .network
            )
            return try await existing.value
        }

        logger.debug(
            SparkNetworkingStrings.Backend.callbackCacheMiss(
                key: key,
                operation: operationName,
                business: businessPurpose
            ),
            module: .network
        )

        let task = Task<SparkNetworkResponse, Error> {
            try await taskFactory()
        }
        inFlight[key] = task

        defer {
            inFlight[key] = nil
        }

        return try await task.value
    }
}
