import Foundation

/// 网络模块统一日志文案。
/// 设计参考 purchases-ios 的 `Strings.xxx` 结构，
/// 让网络层日志具备稳定分类和可检索性。
enum SparkNetworkingStrings {

    enum Backend {
        static let initialized = "Backend 初始化完成，已装配 HTTPClient、Operation、CallbackCache"

        nonisolated static func executing(api: String, operation: String) -> String {
            "Backend 即将执行 API=\(api)，Operation=\(operation)"
        }

        nonisolated static func callbackCacheHit(key: String, operation: String) -> String {
            "Operation 复用进行中的请求，operation=\(operation)，cacheKey=\(key)"
        }

        nonisolated static func callbackCacheMiss(key: String, operation: String) -> String {
            "Operation 首次发起请求，operation=\(operation)，cacheKey=\(key)"
        }
    }

    enum HTTPClient {
        nonisolated static func startingRequest(method: String, path: String) -> String {
            "开始网络请求：\(method) \(path)"
        }

        nonisolated static func queuedRequest(method: String, path: String, count: Int) -> String {
            "当前有请求执行中，已将请求排队：\(method) \(path)，队列剩余 \(count)"
        }

        nonisolated static func finishedRequest(method: String?, path: String?, count: Int) -> String {
            "请求执行完成：\(method ?? "-") \(path ?? "-")，队列剩余 \(count)"
        }

        nonisolated static func retryingRequest(method: String, path: String, retry: Int, delay: TimeInterval) -> String {
            "请求准备重试：\(method) \(path)，第 \(retry) 次重试，延迟 \(delay)s"
        }

        nonisolated static func completedRequest(method: String, path: String, statusCode: Int) -> String {
            "请求完成：\(method) \(path)，HTTP \(statusCode)"
        }

        nonisolated static func failedRequest(method: String, path: String, reason: String) -> String {
            "请求失败：\(method) \(path)，原因：\(reason)"
        }

        nonisolated static func authRefreshTriggered(path: String) -> String {
            "检测到 401，准备刷新令牌后重试：\(path)"
        }

        nonisolated static func outbound(
            method: String,
            path: String,
            requestId: String,
            headers: String,
            body: String
        ) -> String {
            "发送请求：\(method) \(path) rid=\(requestId) headers=\(headers) body=\(body)"
        }

        nonisolated static func inbound(
            method: String,
            path: String,
            requestId: String,
            statusCode: Int,
            cost: TimeInterval,
            headers: String,
            body: String
        ) -> String {
            "接收响应：\(method) \(path) rid=\(requestId) status=\(statusCode) cost=\(String(format: "%.3f", cost))s headers=\(headers) body=\(body)"
        }

        /// 与「发送请求」同一脱敏规则下的 body；在 HTTP 非 2xx 时再记一条，避免只复制往返分隔块时丢失原报文。
        nonisolated static func requestBodyReplayForNonSuccess(
            method: String,
            path: String,
            requestId: String,
            body: String
        ) -> String {
            "非 2xx，重复记录请求体：\(method) \(path) rid=\(requestId) body=\(body)"
        }
    }

    enum ETag {
        nonisolated static func apply(tag: String, key: String) -> String {
            "附加 If-None-Match，etag=\(tag)，cacheKey=\(key)"
        }

        nonisolated static func hit304(key: String) -> String {
            "收到 304，使用本地缓存体恢复响应，cacheKey=\(key)"
        }

        nonisolated static func store(tag: String, key: String) -> String {
            "更新 ETag 缓存，etag=\(tag)，cacheKey=\(key)"
        }
    }

    enum Auth {
        nonisolated static func refreshing() -> String {
            "访问令牌即将过期或已失效，开始刷新令牌"
        }

        nonisolated static func refreshSucceeded() -> String {
            "令牌刷新成功"
        }

        nonisolated static func refreshFailed() -> String {
            "令牌刷新失败，已清理本地认证信息"
        }
    }
}
