import Foundation
import Combine

@MainActor
final class TaskStatisticsStore: ObservableObject {
    @Published private(set) var statistics: TaskStatistics = .empty
    @Published private(set) var selectedPeriod: TaskStatisticsPeriod = .days7
    @Published private(set) var isLoadingExecutions = false

    private var executions: [TaskExecutionRecord] = []
    private var tasks: [HealthTask] = []

    func update(tasks: [HealthTask], executions: [TaskExecutionRecord], period: TaskStatisticsPeriod? = nil) {
        self.tasks = tasks
        self.executions = executions
        if let period {
            selectedPeriod = period
        }
        refreshStatistics()
    }

    func setPeriod(_ period: TaskStatisticsPeriod) {
        selectedPeriod = period
        refreshStatistics()
    }

    func refreshStatistics(now: Date = Date()) {
        statistics = TaskStatisticsBuilder.build(
            tasks: tasks,
            executions: executions,
            period: selectedPeriod,
            now: now
        )
    }

    func mergeExecutions(_ incoming: [TaskExecutionRecord]) {
        var map = Dictionary(uniqueKeysWithValues: executions.map { ($0.id, $0) })
        for record in incoming {
            map[record.id] = record
        }
        executions = Array(map.values)
        refreshStatistics()
    }
}
