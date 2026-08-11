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
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                TaskListOverviewHeader(overview: overview)

                TaskFilterBar(filters: $filters)

                TaskSortBar()
                    .padding(.top, 8)
                    .padding(.bottom, 10)

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
                    .padding(.horizontal, 16)

                    syncFooterText
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                    Spacer()
                } else {
                    List {
                        ForEach(visibleTasks) { task in
                            TaskListRowView(
                                task: task,
                                isSubmittingExecution: taskManager.isSubmittingExecution,
                                onComplete: {
                                    Task {
                                        try? await taskManager.executionRecorder.submit(task: task, status: .done)
                                    }
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectTask(task)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .onAppear {
                                guard task.id == visibleTasks.last?.id else { return }
                                Task { await taskManager.syncIncremental(memberID: memberID) }
                            }
                        }

                        if taskManager.lastSyncTime != nil || taskManager.lastSyncError != nil {
                            syncFooterText
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                                .padding(.bottom, 86)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else {
                            Color.clear
                                .frame(height: 86)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.bottom, 96, for: .scrollContent)
                    .refreshable {
                        await taskManager.syncIncremental(memberID: memberID)
                    }
                }
            }

            createButton
        }
        .animation(.easeInOut(duration: 0.25), value: filters)
    }

    @ViewBuilder
    private var syncFooterText: some View {
        if let lastSync = taskManager.lastSyncTime {
            Text(String(format: NSLocalizedString("task.sync.last", comment: "上次同步: %@"), formatSyncTime(lastSync)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let error = taskManager.lastSyncError, error.isEmpty == false {
            Text(error)
                .font(.caption2)
                .foregroundStyle(Color(uiColor: .systemRed))
        }
    }

    private var createButton: some View {
        Button(action: onCreate) {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor, in: Circle())
                .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 8)
        }
        .accessibilityLabel(NSLocalizedString("task.empty.create", comment: "新建任务"))
        .padding(.trailing, 20)
        .padding(.bottom, 18)
    }

    private func formatSyncTime(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }
}

struct TaskListRowView: View {
    let task: HealthTask
    let isSubmittingExecution: Bool
    let onComplete: () -> Void

    private var overdue: Bool {
        TaskDateHelper.isOverdue(task)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TaskCompletionToggle(
                task: task,
                isSubmitting: isSubmittingExecution,
                onComplete: onComplete
            )
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if task.description.isEmpty == false {
                            Text(task.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)

                    TaskPriorityBadge(priority: task.priority)
                }

                HStack(spacing: 8) {
                    TaskTypeBadge(type: task.type)

                    if overdue {
                        Text(NSLocalizedString("task.status.overdue", comment: "已过期"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .systemRed).opacity(0.12), in: Capsule())
                            .foregroundStyle(Color(uiColor: .systemRed))
                    }

                    Spacer(minLength: 0)

                    Text(TaskDateHelper.relativeTimeLabel(task))
                        .font(.caption)
                        .foregroundStyle(overdue ? Color(uiColor: .systemRed) : .secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
        )
    }
}

struct TaskCompletionToggle: View {
    let task: HealthTask
    let isSubmitting: Bool
    let onComplete: () -> Void

    var body: some View {
        Button {
            guard task.status == .pending, isSubmitting == false else { return }
            onComplete()
        } label: {
            Image(systemName: iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(task.status != .pending || isSubmitting)
        .accessibilityLabel(task.status == .pending
            ? NSLocalizedString("task.action.complete", comment: "标记完成")
            : task.status.displayName)
    }

    private var iconName: String {
        switch task.status {
        case .pending:
            return "circle"
        case .completed:
            return "checkmark.circle.fill"
        case .canceled:
            return "minus.circle"
        }
    }

    private var iconColor: Color {
        switch task.status {
        case .pending:
            return Color(uiColor: .tertiaryLabel)
        case .completed:
            return Color(uiColor: .systemGreen)
        case .canceled:
            return Color(uiColor: .secondaryLabel)
        }
    }
}

struct TaskPriorityBadge: View {
    let priority: HealthTask.Priority

    var body: some View {
        Text(priority.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(priority.backgroundColor, in: Capsule())
            .foregroundStyle(priority.accentColor)
    }
}

struct TaskTypeBadge: View {
    let type: HealthTask.TaskType

    var body: some View {
        Label(type.displayName, systemImage: type.iconName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(type.backgroundColor, in: Capsule())
            .foregroundStyle(type.accentColor)
    }
}
