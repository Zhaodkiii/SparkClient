import Foundation

/// 问报告工具：在 `RemoteMemberCompleteData` 上映射、筛选可引用健康资料（复用 M2 时间轴映射）。
enum ChatHealthResourceSourceLister {
    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let filterDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    static func list(
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        resourceTypes: [String]?,
        keyword: String?,
        startDate: String?,
        endDate: String?,
        limit: Int
    ) -> (candidates: [HealthResourceToolCandidateDTO], truncated: Bool) {
        let mapped = ChatAskReportTimelineMapper.map(data)
        var sources: [ChatSelectableHealthSource] = mapped.allSelectableSources

        if let resourceTypes, resourceTypes.isEmpty == false {
            let allowed = Set(resourceTypes.compactMap { HealthResourceType(rawValue: $0) })
            if allowed.isEmpty == false {
                sources = sources.filter { allowed.contains($0.resourceType) }
            }
        }

        let normalizedKeyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let normalizedKeyword, normalizedKeyword.isEmpty == false {
            sources = sources.filter { matchesKeyword($0, query: normalizedKeyword) }
        }

        let start = parseFilterDate(startDate)
        let end = parseFilterDate(endDate)
        if start != nil || end != nil {
            sources = sources.filter { inDateRange($0.occurredAt, start: start, end: end) }
        }

        sources.sort { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }

        let cap = max(1, min(limit, 50))
        let truncated = sources.count > cap
        let slice = Array(sources.prefix(cap))
        let candidates = slice.map { toCandidate($0, keyword: normalizedKeyword) }
        return (candidates, truncated)
    }

    private static func toCandidate(
        _ source: ChatSelectableHealthSource,
        keyword: String?
    ) -> HealthResourceToolCandidateDTO {
        let match = matchMetadata(source: source, keyword: keyword)
        return HealthResourceToolCandidateDTO(
            resourceType: source.resourceType.rawValue,
            resourceId: source.resourceID,
            memberId: source.memberID,
            title: source.title,
            occurredAt: formatDate(source.occurredAt),
            institution: source.subtitle,
            matchedFields: match.fields,
            matchReason: match.reason,
            confidence: match.confidence
        )
    }

    private static func matchMetadata(
        source: ChatSelectableHealthSource,
        keyword: String?
    ) -> (fields: [String], reason: String, confidence: Double) {
        guard let keyword, keyword.isEmpty == false else {
            return ([], L10n.text("chat.ask_report.tool.match.all_in_tab"), 0.88)
        }
        var fields: [String] = []
        if source.title.localizedCaseInsensitiveContains(keyword) { fields.append("title") }
        if source.subtitle?.localizedCaseInsensitiveContains(keyword) == true { fields.append("subtitle") }
        if source.summary?.localizedCaseInsensitiveContains(keyword) == true { fields.append("summary") }
        if source.searchText.contains(keyword) { fields.append("searchText") }
        let reason = fields.isEmpty
            ? L10n.text("chat.ask_report.tool.match.weak")
            : L10n.format("chat.ask_report.tool.match.keyword_format", keyword)
        let confidence: Double = fields.contains("title") ? 0.88 : (fields.isEmpty ? 0.42 : 0.72)
        return (fields, reason, confidence)
    }

    private static func matchesKeyword(_ source: ChatSelectableHealthSource, query: String) -> Bool {
        source.searchText.contains(query)
            || source.title.localizedCaseInsensitiveContains(query)
            || (source.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
            || (source.summary?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private static func inDateRange(_ date: Date?, start: Date?, end: Date?) -> Bool {
        guard let date else { return start == nil && end == nil }
        if let start, date < start { return false }
        if let end {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
            if date >= endOfDay { return false }
        }
        return true
    }

    private static func parseFilterDate(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false else {
            return nil
        }
        return filterDateFormatter.date(from: text)
    }

    private static func formatDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return displayDateFormatter.string(from: date)
    }
}
