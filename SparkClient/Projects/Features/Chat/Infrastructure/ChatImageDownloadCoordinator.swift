import Foundation

/// 同一张聊天图片在列表与详情、或多次滚动出现时共用一个下载任务，避免并发重复请求。
actor ChatImageDownloadCoordinator {
    static let shared = ChatImageDownloadCoordinator()

    private var inflight: [String: Task<URL, Error>] = [:]

    func cachedOrDownload(
        dedupeKey: String,
        operation: @Sendable @escaping () async throws -> URL
    ) async throws -> URL {
        if let existing = inflight[dedupeKey] {
            return try await existing.value
        }
        let task = Task {
            try await operation()
        }
        inflight[dedupeKey] = task
        do {
            let url = try await task.value
            inflight[dedupeKey] = nil
            return url
        } catch {
            inflight[dedupeKey] = nil
            throw error
        }
    }
}
