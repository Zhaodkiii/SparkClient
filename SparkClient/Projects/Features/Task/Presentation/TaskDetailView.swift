import SwiftUI

struct TaskDetailView: View {
    let memberID: Int?
    @ObservedObject var taskManager: TaskManager
    let taskID: Int

    @State private var showEdit = false
    @State private var showRepeatEditSheet = false
    @State private var pendingEditScope: TaskRepeatEditScope = .instance
    @State private var showCancelConfirm = false
    @State private var actionError: String?

    private var task: HealthTask? {
        taskManager.task(for: taskID)
    }

    private var detailModel: TaskDetailModel? {
        task.map { TaskDetailModelBuilder.make(task: $0) }
    }

    var body: some View {
        Group {
            if let task, let detailModel {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        generalSection(task: task, detailModel: detailModel)
                        TaskBusinessPanelView(task: task)

                        if detailModel.canExecute {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(NSLocalizedString("task.detail.actions", comment: "执行操作"))
                                    .font(.subheadline.weight(.semibold))
                                TaskExecutionActionSheet(
                                    isSubmitting: taskManager.isSubmittingExecution,
                                    onDone: { submitExecution(status: .done) },
                                    onSkip: { submitExecution(status: .skipped) },
                                    onFail: { submitExecution(status: .failed) }
                                )
                            }
                        }

                        executionHistorySection(task: task)
                    }
                    .padding(16)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(NSLocalizedString("task.detail.title", comment: "任务详情"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if detailModel?.canEdit == true {
                    Menu {
                        Button(NSLocalizedString("task.action.edit", comment: "修改任务")) {
                            beginEdit()
                        }
                        Button(NSLocalizedString("task.action.cancel", comment: "取消任务"), role: .destructive) {
                            showCancelConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            await taskManager.loadExecutions(taskID: taskID)
        }
        .sheet(isPresented: $showEdit) {
            CompatibleNavigationContainer {
                TaskCreateView(
                    memberID: memberID,
                    taskManager: taskManager,
                    mode: .edit(taskID: taskID, scope: pendingEditScope),
                    onDismiss: { showEdit = false }
                )
            }
        }
        .sheet(isPresented: $showRepeatEditSheet) {
            TaskRepeatEditSheet(
                onSelectInstance: {
                    pendingEditScope = .instance
                    showRepeatEditSheet = false
                    showEdit = true
                },
                onSelectPlan: {
                    pendingEditScope = .plan
                    showRepeatEditSheet = false
                    showEdit = true
                },
                onCancel: {
                    showRepeatEditSheet = false
                }
            )
        }
        .alert(
            NSLocalizedString("task.action.cancel", comment: "取消任务"),
            isPresented: $showCancelConfirm
        ) {
            Button(NSLocalizedString("common.cancel", comment: "取消"), role: .cancel) {}
            Button(NSLocalizedString("task.action.cancel", comment: "取消任务"), role: .destructive) {
                Task {
                    try? await taskManager.cancelTask(taskID: taskID)
                }
            }
        } message: {
            Text(NSLocalizedString("task.cancel.confirm", comment: "确定要取消此任务吗？"))
        }
        .alert(
            NSLocalizedString("common.error", comment: "Error"),
            isPresented: Binding(
                get: { actionError != nil },
                set: { if $0 == false { actionError = nil } }
            )
        ) {
            Button(NSLocalizedString("common.ok", comment: "OK"), role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private func generalSection(task: HealthTask, detailModel: TaskDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.title)
                .font(.title2.weight(.semibold))

            if task.description.isEmpty == false {
                Text(task.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            detailRow(
                NSLocalizedString("task.field.status", comment: "状态"),
                detailModel.overdue
                    ? NSLocalizedString("task.status.overdue_pending", comment: "已过期 / 待处理")
                    : task.status.displayName,
                valueColor: detailModel.overdue ? .red : nil
            )
            detailRow(NSLocalizedString("task.field.priority", comment: "优先级"), task.priority.displayName)
            detailRow(NSLocalizedString("task.field.time", comment: "时间"), TaskDateHelper.relativeTimeLabel(task))
            detailRow(NSLocalizedString("task.field.repeat", comment: "重复"), task.repeatType.displayName)
            detailRow(NSLocalizedString("task.field.source", comment: "来源"), task.source.displayName)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func executionHistorySection(task: HealthTask) -> some View {
        let records = taskManager.executions(for: task.id)
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("task.detail.executions", comment: "最近执行记录"))
                .font(.subheadline.weight(.semibold))

            if records.isEmpty {
                Text(NSLocalizedString("task.detail.no_executions", comment: "暂无执行记录"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records.prefix(10)) { record in
                    HStack {
                        Text(record.status.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(executionColor(record.status))
                        Text(task.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(DateFormatter.localizedString(from: record.executedAt, dateStyle: .short, timeStyle: .short))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor ?? .primary)
        }
    }

    private func beginEdit() {
        guard let task else { return }
        if task.repeatType != .none {
            showRepeatEditSheet = true
        } else {
            pendingEditScope = .instance
            showEdit = true
        }
    }

    private func submitExecution(status: TaskExecutionStatus) {
        guard let task else { return }
        Task {
            do {
                try await taskManager.executionRecorder.submit(task: task, status: status)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func executionColor(_ status: TaskExecutionStatus) -> Color {
        switch status {
        case .done: return .green
        case .skipped: return Color(uiColor: .systemTeal)
        case .failed: return .red
        }
    }
}
