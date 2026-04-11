import Foundation

enum SparkOSSConfigurationError: Error {
    /// STS 返回缺少 bucket/region/endpoint 或 AccessKey
    case incompleteSTSResponse
}

/// 登录后预拉取并缓存阿里云 OSS STS 与桶信息，供后续直传复用。
@MainActor
final class SparkOSSConfigurationStore {
    private(set) var snapshot: AliyunOSSRuntimeConfig?

    private let logger: Logger

    init(logger: Logger = ConsoleLogger()) {
        self.logger = logger
    }

    /// 冷启动 / 登录后由 `AppBootstrapper` 调用：尽力拉取，失败只打日志。
    func prefetchFromBackend(using api: SparkOSSAPI) async {
        do {
            let response = try await api.getSTSCredentials()
            guard let cfg = AliyunOSSRuntimeConfig(response: response) else {
                logger.warning("OSS STS 预拉取：字段不完整，未缓存", module: .oss)
                return
            }
            snapshot = cfg
            logger.info(
                "OSS 配置已加载 bucket=\(cfg.bucketName) region=\(cfg.region)",
                module: .oss
            )
        } catch {
            logger.warning(
                "OSS STS 预拉取失败（后续上传前将重试）：\(error.localizedDescription)",
                module: .oss
            )
        }
    }

    func clear() {
        snapshot = nil
    }

    /// 上传前调用：优先用缓存；无缓存或临近过期则向服务端刷新。
    func configurationForUpload(using api: SparkOSSAPI) async throws -> AliyunOSSRuntimeConfig {
        if let s = snapshot, s.isFresh(thresholdSeconds: 300) {
            return s
        }
        let response = try await api.getSTSCredentials()
        guard let cfg = AliyunOSSRuntimeConfig(response: response) else {
            throw SparkOSSConfigurationError.incompleteSTSResponse
        }
        snapshot = cfg
        return cfg
    }
}
