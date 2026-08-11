import SwiftUI

struct TaskFilterBar: View {
    @Binding var filters: TaskFilterSelection

    var body: some View {
        Picker("task_filter_status", selection: $filters.status) {
            ForEach(TaskStatusFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }
}

struct TaskSortBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("task.sort.rule", comment: "排序: 截止时间优先 + 优先级"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

struct TaskListOverviewHeader: View {
    let overview: TaskListOverview

    var body: some View {
        HStack(spacing: 18) {
            metric(value: overview.pendingCount, label: NSLocalizedString("task.overview.pending", comment: "待完成"))
            metric(value: overview.overdueCount, label: NSLocalizedString("task.overview.overdue", comment: "逾期"), tint: .red)
            metric(value: overview.todayCount, label: NSLocalizedString("task.overview.today", comment: "今日"))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func metric(value: Int, label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
