import Foundation

/// 网络 Operation 协议。
/// 每个接口都被抽象成独立的 Operation，便于统一调度、日志和回调合并。
protocol SparkNetworkOperation: Sendable {
    var name: String { get }
    var apiName: String { get }
    var request: SparkNetworkRequest { get }
    var callbackCacheKey: String? { get }

    func execute(with engine: SparkNetworkEngine) async throws -> SparkNetworkResponse
}

extension SparkNetworkOperation {
    func execute(with engine: SparkNetworkEngine) async throws -> SparkNetworkResponse {
        try await engine.sendRaw(request)
    }
}

/// 面向缓存型 GET 请求的基础 Operation。
/// 默认会将 `method + path + query` 作为回调合并 key。
struct CacheableSparkNetworkOperation: SparkNetworkOperation {
    let name: String
    let apiName: String
    let request: SparkNetworkRequest

    var callbackCacheKey: String? {
        guard request.method == .get else { return nil }

        let query = request.queryItems?
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&") ?? ""

        return "\(request.method.rawValue)|\(request.path)|\(query)"
    }
}
