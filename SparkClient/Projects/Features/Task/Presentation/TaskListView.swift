import SwiftUI

struct TaskListView: View {
    let memberID: Int?
    @ObservedObject var taskManager: TaskManager
    @Binding var filters: TaskFilterSelection
    let onSelectTask: (HealthTask) -> Void
    let onCreate: () -> Void

    private var visibleTasks: [HealthTask] {
        taskManager.visibleTasks(filters: filters, memberID: memberID)
    }

    private var overview: TaskListOverview {
        taskManager.listOverview(memberID: memberID)
    }

    var body: some View {
        VStack(spacing: 0) {
            TaskListOverviewHeader(overview: overview)

            TaskFilterBar(filters: $filters)
                .padding(.top, 8)

            TaskSortBar()
                .padding(.vertical, 8)

            if taskManager.isSyncing && taskManager.tasks.isEmpty {
                TaskLoadingSkeletonView()
                Spacer()
            } else if visibleTasks.isEmpty {
                TaskEmptyStateView(
                    onCreate: onCreate,
                    onRefresh: {
                        Task { await taskManager.syncIncremental(memberID: memberID) }
                    }
                )
                Spacer()
            } else {
                List {
                    ForEach(visibleTasks) { task in
                        Button {
                            onSelectTask(task)
                        } label: {
                            TaskListRowView(task: task)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            guard task.id == visibleTasks.last?.id else { return }
                            Task { await taskManager.syncIncremental(memberID: memberID) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await taskManager.syncIncremental(memberID: memberID)
                }
            }

            if let lastSync = taskManager.lastSyncTime {
                Text(String(format: NSLocalizedString("task.sync.last", comment: "上次同步: %@"), formatSyncTime(lastSync)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: filters)
    }

    private func formatSyncTime(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }
}

struct TaskListRowView: View {
    let task: HealthTask

    private var overdue: Bool {
        TaskDateHelper.isOverdue(task)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(task.type.displayName)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(typeColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(typeColor)

                Text(task.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            if task.description.isEmpty == false {
                Text(task.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(task.status.displayName)
                    .font(.caption)
                    .foregroundStyle(statusColor)

                if overdue {
                    Text(NSLocalizedString("task.status.overdue", comment: "已过期"))
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }

                Text(task.priority.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                    .foregroundStyle(task.priority == .high ? .orange : .secondary)

                Spacer()

                Text(TaskDateHelper.relativeTimeLabel(task))
                    .font(.caption)
                    .foregroundStyle(overdue ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var typeColor: Color {
        switch task.type {
        case .medical: return .red
        case .exercise: return .green
        case .diet: return .orange
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .pending: return .orange
        case .completed: return .green
        case .canceled: return .red
        }
    }
}
