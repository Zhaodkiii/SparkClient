import SwiftUI

struct SmallTasksSettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel

    /// 当前正在编辑的任务（nil = 不展示 sheet）
    @State private var editingTask: SmallTask?
    @State private var selectedSource: TaskSource = .local

    /// 删除确认
    @State private var pendingDelete: SmallTask?

    private var filteredTasks: [SmallTask] {
        viewModel.effectiveSmallTasks
            .filter { $0.source == selectedSource }
            .sorted { $0.code < $1.code }
    }

    var body: some View {
        List {
            Section {
                Picker(
                    L10n.text(
                        "ai_settings.small_tasks.source.filter",
                        fallback: "Source",
                        comment: "Small task source filter"
                    ),
                    selection: $selectedSource
                ) {
                    Text(
                        L10n.text(
                            "ai_settings.small_tasks.source.local",
                            fallback: "Local",
                            comment: "Local small tasks"
                        )
                    )
                    .tag(TaskSource.local)

                    Text(
                        L10n.text(
                            "ai_settings.small_tasks.source.service",
                            fallback: "Service",
                            comment: "Service small tasks"
                        )
                    )
                    .tag(TaskSource.service)
                }
                .pickerStyle(.segmented)
            }

            Section {
                if filteredTasks.isEmpty {
                    Text(
                        L10n.text(
                            selectedSource.emptyLocalizationKey,
                            fallback: "No small tasks",
                            comment: "Empty small tasks list"
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredTasks) { task in
                        MainNavigationLink {
                            SmallTaskDetailView(
                                viewModel: viewModel,
                                taskCode: task.code,
                                source: task.source
                            )
                        } label: {
                            SmallTaskRow(task: task)
                        }
                        .swipeActions {
                            if task.source == .local {
                                Button(role: .destructive) {
                                    pendingDelete = task
                                } label: {
                                    Label(
                                        L10n.text("common.delete", fallback: "Delete", comment: "Delete action"),
                                        systemImage: "trash"
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(
            L10n.text(
                "ai_settings.small_tasks.nav.title",
                fallback: "Small tasks",
                comment: "Small tasks settings title"
            )
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedSource == .local {
                    Button {
                        editingTask = nil
                        editingTask = SmallTask.newDraft(id: viewModel.nextLocalSmallTaskID())
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }

        /// ✅ 核心：用 item sheet（彻底解决 nil 问题）
        .sheet(item: $editingTask) { task in
            CompatibleNavigationContainer {
                SmallTaskEditorView(
                    task: task,
                    nextID: viewModel.nextLocalSmallTaskID(),
                    promptTooling: viewModel.promptTooling,
                    promptTemplates: viewModel.snapshot.promptRepo
                ) { updatedTask in
                    Task {
                        await viewModel.upsertLocalSmallTaskAndPersist(updatedTask)
                    }
                    editingTask = nil
                }
            }
        }

        /// 删除确认
        .alert(
            L10n.text(
                "ai_settings.small_tasks.delete.title",
                fallback: "Delete small task?",
                comment: "Delete small task alert title"
            ),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if $0 == false { pendingDelete = nil } }
            )
        ) {
            Button(
                L10n.text("common.cancel", fallback: "Cancel", comment: "Cancel action"),
                role: .cancel
            ) {
                pendingDelete = nil
            }

            Button(
                L10n.text("common.delete", fallback: "Delete", comment: "Delete action"),
                role: .destructive
            ) {
                if let task = pendingDelete {
                    Task {
                        await viewModel.deleteLocalSmallTaskAndPersist(code: task.code)
                    }
                }
                pendingDelete = nil
            }
        }
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshEffectiveSmallTasks()
        }
    }
}

private struct SmallTaskRow: View {
    let task: SmallTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.icon.isEmpty ? "checklist" : task.icon)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(task.name)

                    Text(task.source.localizedTitle)
                        .font(.caption2)
                        .foregroundStyle(task.source == .local ? .blue : .purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((task.source == .local ? Color.blue : Color.purple).opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(task.brief.isEmpty ? task.code : task.brief)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private extension TaskSource {
    var localizedTitle: String {
        switch self {
        case .local:
            return L10n.text("ai_settings.small_tasks.source.local", fallback: "Local", comment: "Local small task source")
        case .service:
            return L10n.text("ai_settings.small_tasks.source.service", fallback: "Service", comment: "Service small task source")
        }
    }

    var emptyLocalizationKey: String {
        switch self {
        case .local:
            return "ai_settings.small_tasks.empty.local"
        case .service:
            return "ai_settings.small_tasks.empty.service"
        }
    }
}

extension SmallTask {

    /// 创建一个“草稿任务”（用于 UI 编辑）
    static func newDraft(id: Int) -> SmallTask {
        SmallTask(
            id: id,
            name: "",
            code: "Local_\(id)",   // ⚠️ 提前生成 code，保证 id 稳定
            brief: "",
            prompt: "",
            icon: "checklist",
            toolList: [],
            source: .local
        )
    }
}
