import SwiftUI

struct TaskCenterViewController: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case pending
        case completed
        case canceled

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return NSLocalizedString("common.all", comment: "All")
            case .pending: return NSLocalizedString("task.filter.pending", comment: "待完成")
            case .completed: return NSLocalizedString("task.filter.completed", comment: "已完成")
            case .canceled: return NSLocalizedString("task.filter.canceled", comment: "已取消")
            }
        }
    }

    struct TaskFormDraft {
        var title: String = ""
        var description: String = ""
    }

    let memberID: Int?

    @ObservedObject var taskManager: TaskManager
    @State private var filter: Filter = .all
    @State private var isCreating = false
    @State private var editingTask: HealthTask?
    @State private var createDraft = TaskFormDraft()
    @State private var editDraft = TaskFormDraft()

    private var filteredTasks: [HealthTask] {
        let base: [HealthTask]
        switch filter {
        case .all:
            base = taskManager.tasks
        case .pending:
            base = taskManager.tasks.filter { $0.status == .pending }
        case .completed:
            base = taskManager.tasks.filter { $0.status == .completed }
        case .canceled:
            base = taskManager.tasks.filter { $0.status == .canceled }
        }
        return base.sorted { lhs, rhs in
            let left = lhs.dueTime ?? lhs.startTime ?? lhs.updatedAt
            let right = rhs.dueTime ?? rhs.startTime ?? rhs.updatedAt
            if left == right { return lhs.updatedAt > rhs.updatedAt }
            return left < right
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("task_filter", selection: $filter) {
                ForEach(Filter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            List {
                ForEach(filteredTasks) { task in
                    taskRow(task)
                        .onAppear {
                            // 简单增量加载：滑到尾部时触发一次同步。
                            guard task.id == filteredTasks.last?.id else { return }
                            Task { await taskManager.syncIncremental(memberID: memberID) }
                        }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await taskManager.syncIncremental(memberID: memberID)
            }
        }
        .navigationTitle(NSLocalizedString("task.center.title", comment: "任务中心"))
        .task {
            await taskManager.loadInitial(memberID: memberID)
            await taskManager.syncIncremental(memberID: memberID)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    createDraft = TaskFormDraft()
                    isCreating = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            CompatibleNavigationContainer {
                TaskFormView(
                    title: NSLocalizedString("task.create.title", comment: "创建任务"),
                    draft: $createDraft,
                    onSave: {
                        Task {
                            let payload = TaskCreatePayload(
                                member: memberID ?? 0,
                                title: createDraft.title,
                                description: createDraft.description,
                                type: .medical,
                                status: .pending,
                                startTime: nil,
                                dueTime: nil,
                                repeatType: .none,
                                priority: .medium,
                                businessType: "manual",
                                businessID: "",
                                extra: [:],
                                taskMedical: TaskMedicalPayload(
                                    reminderTime: nil,
                                    medicalTaskType: "general_medical",
                                    description: createDraft.description,
                                    source: "manual",
                                    extra: [:]
                                ),
                                taskExercise: nil,
                                taskDiet: nil
                            )
                            try? await taskManager.createTask(payload: payload)
                            isCreating = false
                        }
                    },
                    onCancel: {
                        isCreating = false
                    }
                )
            }
        }
        .sheet(item: $editingTask) { task in
            CompatibleNavigationContainer {
                TaskFormView(
                    title: NSLocalizedString("task.edit.title", comment: "修改任务"),
                    draft: Binding(
                        get: { editDraft },
                        set: { editDraft = $0 }
                    ),
                    onSave: {
                        Task {
                            let payload = TaskUpdatePayload(
                                title: editDraft.title,
                                description: editDraft.description,
                                status: nil,
                                startTime: nil,
                                dueTime: nil,
                                repeatType: nil,
                                priority: nil,
                                extra: nil,
                                taskMedical: nil,
                                taskExercise: nil,
                                taskDiet: nil
                            )
                            try? await taskManager.updateTask(taskID: task.id, payload: payload)
                            editingTask = nil
                        }
                    },
                    onCancel: {
                        editingTask = nil
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ task: HealthTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.title)
                    .font(.headline)
                Spacer()
                Text(task.type.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            if task.description.isEmpty == false {
                Text(task.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text(task.status.displayName)
                    .font(.caption)
                    .foregroundStyle(statusColor(task.status))

                Spacer()

                Text(taskTime(task))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(NSLocalizedString("task.action.cancel", comment: "取消任务"), role: .destructive) {
                Task { try? await taskManager.cancelTask(taskID: task.id) }
            }

            Button(NSLocalizedString("task.action.complete", comment: "完成任务")) {
                Task { try? await taskManager.completeTask(taskID: task.id) }
            }
            .tint(.green)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(NSLocalizedString("task.action.edit", comment: "修改任务")) {
                editDraft = TaskFormDraft(title: task.title, description: task.description)
                editingTask = task
            }
            .tint(.blue)
        }
    }

    private func statusColor(_ status: HealthTask.TaskStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .completed: return .green
        case .canceled: return .red
        }
    }

    private func taskTime(_ task: HealthTask) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        if let due = task.dueTime {
            return formatter.string(from: due)
        }
        if let start = task.startTime {
            return formatter.string(from: start)
        }
        return NSLocalizedString("task.time.unspecified", comment: "未设置时间")
    }
}

private struct TaskFormView: View {
    let title: String
    @Binding var draft: TaskCenterViewController.TaskFormDraft
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("common.title", comment: "Title"), text: $draft.title)
                TextField(NSLocalizedString("task.field.description", comment: "描述"), text: $draft.description)
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("common.cancel", comment: "取消"), action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("common.save", comment: "保存"), action: onSave)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
