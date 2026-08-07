import SwiftUI

struct TaskFilterBar: View {
    @Binding var filters: TaskFilterSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            filterRow(
                title: NSLocalizedString("task.filter.status", comment: "状态"),
                items: TaskStatusFilter.allCases.map { ($0.id, $0.title) },
                selectedID: filters.status.id
            ) { id in
                if let value = TaskStatusFilter.allCases.first(where: { $0.id == id }) {
                    filters.status = value
                }
            }

            filterRow(
                title: NSLocalizedString("task.filter.type", comment: "类型"),
                items: TaskTypeFilter.allCases.map { ($0.id, $0.title) },
                selectedID: filters.type?.id,
                allowsClear: true
            ) { id in
                if let id {
                    filters.type = TaskTypeFilter.allCases.first { $0.id == id }
                } else {
                    filters.type = nil
                }
            }

            filterRow(
                title: NSLocalizedString("task.filter.priority", comment: "优先级"),
                items: TaskPriorityFilter.allCases.map { ($0.id, $0.title) },
                selectedID: filters.priority?.id,
                allowsClear: true
            ) { id in
                if let id {
                    filters.priority = TaskPriorityFilter.allCases.first { $0.id == id }
                } else {
                    filters.priority = nil
                }
            }

            filterRow(
                title: NSLocalizedString("task.filter.time", comment: "时间"),
                items: TaskTimeFilter.allCases.map { ($0.id, $0.title) },
                selectedID: filters.time?.id,
                allowsClear: true
            ) { id in
                if let id {
                    filters.time = TaskTimeFilter.allCases.first { $0.id == id }
                } else {
                    filters.time = nil
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func filterRow(
        title: String,
        items: [(String, String)],
        selectedID: String?,
        allowsClear: Bool = false,
        onSelect: @escaping (String?) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if allowsClear {
                        chip(title: NSLocalizedString("common.all", comment: "All"), isSelected: selectedID == nil) {
                            onSelect(nil)
                        }
                    }
                    ForEach(items, id: \.0) { item in
                        chip(title: item.1, isSelected: selectedID == item.0) {
                            onSelect(item.0)
                        }
                    }
                }
            }
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.22), value: isSelected)
    }
}

struct TaskSortBar: View {
    var body: some View {
        HStack {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption)
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
        HStack(spacing: 16) {
            metric(value: overview.pendingCount, label: NSLocalizedString("task.overview.pending", comment: "待完成"))
            metric(value: overview.overdueCount, label: NSLocalizedString("task.overview.overdue", comment: "逾期"), tint: .red)
            metric(value: overview.todayCount, label: NSLocalizedString("task.overview.today", comment: "今日"))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func metric(value: Int, label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
