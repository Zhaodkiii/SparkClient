import Foundation

struct TaskStatistics: Equatable, Sendable {
    let totalCount: Int
    let doneCount: Int
    let skippedCount: Int
    let failedCount: Int
    let overdueCount: Int
    let todayDoneCount: Int
    let todaySkippedCount: Int
    let todayFailedCount: Int
    let adherenceTrend: [Double]
    let recentExecutions: [TaskExecutionRecord]

    var completionRate: Double {
        let actionable = doneCount + skippedCount + failedCount
        guard actionable > 0 else { return 0 }
        return Double(doneCount) / Double(actionable)
    }

    static let empty = TaskStatistics(
        totalCount: 0,
        doneCount: 0,
        skippedCount: 0,
        failedCount: 0,
        overdueCount: 0,
        todayDoneCount: 0,
        todaySkippedCount: 0,
        todayFailedCount: 0,
        adherenceTrend: [],
        recentExecutions: []
    )
}

enum TaskStatisticsPeriod: String, CaseIterable, Identifiable, Sendable {
    case days7
    case days30
    case days90

    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .days7: return 7
        case .days30: return 30
        case .days90: return 90
        }
    }

    var title: String {
        switch self {
        case .days7:
            return NSLocalizedString("task.stats.period.7d", comment: "7天")
        case .days30:
            return NSLocalizedString("task.stats.period.30d", comment: "30天")
        case .days90:
            return NSLocalizedString("task.stats.period.90d", comment: "90天")
        }
    }
}

enum TaskStatisticsBuilder {
    static func build(
        tasks: [HealthTask],
        executions: [TaskExecutionRecord],
        period: TaskStatisticsPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskStatistics {
        let startDate = calendar.date(byAdding: .day, value: -(period.dayCount - 1), to: calendar.startOfDay(for: now)) ?? now
        let filteredExecutions = executions.filter { $0.executedAt >= startDate }

        let overdueCount = tasks.filter { TaskDateHelper.isOverdue($0, now: now) }.count
        let todayExecutions = filteredExecutions.filter { calendar.isDateInToday($0.executedAt) }

        let trend = buildAdherenceTrend(
            executions: filteredExecutions,
            period: period,
            now: now,
            calendar: calendar
        )

        let recent = executions
            .sorted { $0.executedAt > $1.executedAt }
            .prefix(20)

        return TaskStatistics(
            totalCount: tasks.count,
            doneCount: filteredExecutions.filter { $0.status == .done }.count,
            skippedCount: filteredExecutions.filter { $0.status == .skipped }.count,
            failedCount: filteredExecutions.filter { $0.status == .failed }.count,
            overdueCount: overdueCount,
            todayDoneCount: todayExecutions.filter { $0.status == .done }.count,
            todaySkippedCount: todayExecutions.filter { $0.status == .skipped }.count,
            todayFailedCount: todayExecutions.filter { $0.status == .failed }.count,
            adherenceTrend: trend,
            recentExecutions: Array(recent)
        )
    }

    private static func buildAdherenceTrend(
        executions: [TaskExecutionRecord],
        period: TaskStatisticsPeriod,
        now: Date,
        calendar: Calendar
    ) -> [Double] {
        guard period.dayCount > 0 else { return [] }

        var trend: [Double] = []
        for offset in stride(from: period.dayCount - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) else {
                trend.append(0)
                continue
            }
            let dayExecutions = executions.filter { calendar.isDate($0.executedAt, inSameDayAs: day) }
            let done = dayExecutions.filter { $0.status == .done }.count
            let total = dayExecutions.count
            trend.append(total > 0 ? Double(done) / Double(total) : 0)
        }
        return trend
    }
}
