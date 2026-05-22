import Foundation

/// 健康资料加载失败分类（摘要卡、AI 上下文、工具解析共用）。
enum HealthResourceLoadError: Error, Equatable, Sendable {
    case notFound
    case forbidden
    case network(String)
    case cancelled
    case invalidType
    case insufficientContent

    static func map(_ error: Error) -> HealthResourceLoadError {
        if error is CancellationError {
            return .cancelled
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
            return .cancelled
        }
        if ns.domain == NSURLErrorDomain {
            return .network(ns.localizedDescription)
        }
        return .network(error.localizedDescription)
    }
}
