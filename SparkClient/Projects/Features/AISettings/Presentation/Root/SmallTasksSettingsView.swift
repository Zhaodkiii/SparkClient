import SwiftUI

struct SmallTasksSettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel
    @State private var editingTask: SmallTask?
    @State private var showingEditor = false
    @State private var pendingDelete: SmallTask?

    private var localTasks: [SmallTask] {
        viewModel.snapshot.smallTasks
            .filter { $0.source == .local }
            .sorted { $0.code < $1.code }
    }

    var body: some View {
        List {
            Section {
                if localTasks.isEmpty {
                    Text("暂无小任务")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(localTasks) { task in
                        Button {
                            editingTask = task
                            showingEditor = true
                        } label: {
                            SmallTaskRow(task: task)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDelete = task
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("小任务")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editingTask = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            CompatibleNavigationContainer {
                SmallTaskEditorView(
                    task: editingTask,
                    nextID: viewModel.nextLocalSmallTaskID()
                ) { task in
                    Task {
                        await viewModel.upsertLocalSmallTaskAndPersist(task)
                    }
                }
            }
        }
        .alert("删除小任务？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if $0 == false { pendingDelete = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let task = pendingDelete {
                    Task { await viewModel.deleteLocalSmallTaskAndPersist(code: task.code) }
                }
                pendingDelete = nil
            }
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
                Text(task.name)
                Text(task.brief.isEmpty ? task.code : task.brief)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SmallTaskEditorView: View {
    let task: SmallTask?
    let nextID: Int
    let onSave: (SmallTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brief = ""
    @State private var prompt = ""
    @State private var icon = "checklist"
    @State private var toolsText = ""

    var body: some View {
        Form {
            Section("基础") {
                TextField("名称", text: $name)
                TextField("简介", text: $brief)
                TextField("图标", text: $icon)
            }
            Section("Prompt") {
                TextEditor(text: $prompt)
                    .frame(minHeight: 160)
            }
            Section("工具") {
                TextField("逗号分隔", text: $toolsText)
            }
        }
        .navigationTitle(task == nil ? "新建小任务" : "编辑小任务")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let id = task?.sourceID ?? nextID
                    let saved = SmallTask.createLocalTask(
                        id: id,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        brief: brief.trimmingCharacters(in: .whitespacesAndNewlines),
                        prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                        icon: icon.trimmingCharacters(in: .whitespacesAndNewlines),
                        toolList: toolsText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false }
                    )
                    onSave(saved)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            guard let task else { return }
            name = task.name
            brief = task.brief
            prompt = task.prompt
            icon = task.icon
            toolsText = task.toolList.joined(separator: ", ")
        }
    }
}
