import SwiftUI

struct TaskStatisticsView: View {
    let memberID: Int?
    @ObservedObject var taskManager: TaskManager

    private var statistics: TaskStatistics {
        taskManager.statisticsStore.statistics
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryHeader
                periodPicker

                if statistics.adherenceTrend.isEmpty {
                    emptyState
                } else {
                    trendSection
                    distributionSection
                    recentExecutionsSection
                }
            }
            .padding(16)
        }
        .navigationTitle(NSLocalizedString("task.stats.title", comment: "统计"))
        .onAppear {
            taskManager.statisticsStore.refreshStatistics()
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("task.stats.completion_rate", comment: "完成率"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(statistics.completionRate * 100))%")
                    .font(.title.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("task.overview.overdue", comment: "逾期"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(statistics.overdueCount)")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.red)
            }

            Spacer()
        }
    }

    private var periodPicker: some View {
        Picker("task_stats_period", selection: Binding(
            get: { taskManager.statisticsStore.selectedPeriod },
            set: { taskManager.statisticsStore.setPeriod($0) }
        )) {
            ForEach(TaskStatisticsPeriod.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("task.stats.empty", comment: "暂无执行记录，先完成几个任务吧"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("task.stats.trend", comment: "依从趋势"))
                .font(.subheadline.weight(.semibold))

            TaskAdherenceTrendChart(values: statistics.adherenceTrend)
                .frame(height: 140)
        }
    }

    private var distributionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("task.stats.distribution", comment: "完成 / 跳过 / 失败分布"))
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                distributionChip(
                    title: NSLocalizedString("task.execution.done", comment: "完成"),
                    count: statistics.doneCount,
                    color: .green
                )
                distributionChip(
                    title: NSLocalizedString("task.execution.skipped", comment: "跳过"),
                    count: statistics.skippedCount,
                    color: Color(uiColor: .systemTeal)
                )
                distributionChip(
                    title: NSLocalizedString("task.execution.failed", comment: "失败"),
                    count: statistics.failedCount,
                    color: .red
                )
            }

            HStack(spacing: 12) {
                todayChip(
                    title: NSLocalizedString("task.stats.today_done", comment: "今日完成"),
                    count: statistics.todayDoneCount
                )
                todayChip(
                    title: NSLocalizedString("task.stats.today_skipped", comment: "今日跳过"),
                    count: statistics.todaySkippedCount
                )
                todayChip(
                    title: NSLocalizedString("task.stats.today_failed", comment: "今日失败"),
                    count: statistics.todayFailedCount
                )
            }
        }
    }

    private var recentExecutionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("task.stats.recent", comment: "最近执行记录"))
                .font(.subheadline.weight(.semibold))

            if statistics.recentExecutions.isEmpty {
                Text(NSLocalizedString("task.detail.no_executions", comment: "暂无执行记录"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(statistics.recentExecutions.prefix(10)) { record in
                    HStack {
                        Text(record.status.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(statusColor(record.status))
                        if let task = taskManager.task(for: record.task) {
                            Text(task.title)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(DateFormatter.localizedString(from: record.executedAt, dateStyle: .short, timeStyle: .short))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func distributionChip(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func todayChip(title: String, count: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusColor(_ status: TaskExecutionStatus) -> Color {
        switch status {
        case .done: return .green
        case .skipped: return Color(uiColor: .systemTeal)
        case .failed: return .red
        }
    }
}

private struct TaskAdherenceTrendChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let stepX = values.count > 1 ? width / CGFloat(values.count - 1) : width

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))

                Path { path in
                    guard values.isEmpty == false else { return }
                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = height - (CGFloat(value) * (height - 16)) - 8
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                Path { path in
                    guard values.isEmpty == false else { return }
                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = height - (CGFloat(value) * (height - 16)) - 8
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.addLine(to: CGPoint(x: CGFloat(values.count - 1) * stepX, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(Color.accentColor.opacity(0.12))
            }
        }
    }
}
