import Foundation

/// 消息流健康资料卡片摘要内存缓存（TTL、成员切换失效、按 key 并发合并）。
actor HealthResourceSummaryCache {
    static let shared = HealthResourceSummaryCache()

    private struct CacheEntry {
        let summary: HealthResourceCardSummary
        let storedAt: Date
        let memberID: Int
    }

    private let ttl: TimeInterval = 300
    private var summaries: [String: CacheEntry] = [:]
    private var inFlight: [String: Task<HealthResourceCardSummary, Never>] = [:]
    private var activeMemberID: Int?

    func setActiveMember(_ memberID: Int?) {
        guard activeMemberID != memberID else { return }
        activeMemberID = memberID
        invalidateAll()
    }

    func summary(for key: String) -> HealthResourceCardSummary? {
        guard let entry = summaries[key], entry.storedAt.addingTimeInterval(ttl) > Date() else {
            summaries[key] = nil
            return nil
        }
        return entry.summary
    }

    func load(
        key: String,
        memberID: Int,
        loader: @Sendable @escaping () async -> HealthResourceCardSummary
    ) async -> HealthResourceCardSummary {
        if let cached = summary(for: key) {
            return cached
        }
        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task {
            let value = await loader()
            await self.store(key: key, memberID: memberID, value: value)
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

    func invalidateAll() {
        summaries.removeAll()
        for (_, task) in inFlight {
            task.cancel()
        }
        inFlight.removeAll()
    }

    func invalidateAll(forMemberID memberID: Int) {
        let keys = summaries.filter { $0.value.memberID == memberID }.map(\.key)
        for key in keys {
            invalidate(key: key)
        }
    }

    private func store(key: String, memberID: Int, value: HealthResourceCardSummary) {
        summaries[key] = CacheEntry(summary: value, storedAt: Date(), memberID: memberID)
    }
}
