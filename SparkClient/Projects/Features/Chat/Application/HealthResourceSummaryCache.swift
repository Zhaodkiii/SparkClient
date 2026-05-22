import Foundation

/// 消息流健康资料卡片摘要内存缓存（按 ref 去重，同 key 并发合并）。
actor HealthResourceSummaryCache {
    static let shared = HealthResourceSummaryCache()

    private var summaries: [String: HealthResourceCardSummary] = [:]
    private var inFlight: [String: Task<HealthResourceCardSummary, Never>] = [:]

    func summary(for key: String) -> HealthResourceCardSummary? {
        summaries[key]
    }

    func load(
        key: String,
        loader: @Sendable @escaping () async -> HealthResourceCardSummary
    ) async -> HealthResourceCardSummary {
        if let cached = summaries[key] {
            return cached
        }
        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task {
            let value = await loader()
            await self.store(key: key, value: value)
            return value
        }
        inFlight[key] = task
        let value = await task.value
        inFlight[key] = nil
        return value
    }

    func invalidate(key: String) {
        summaries[key] = nil
        inFlight[key] = nil
    }

    private func store(key: String, value: HealthResourceCardSummary) {
        summaries[key] = value
    }
}
