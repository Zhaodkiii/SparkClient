import SwiftUI

struct SmallTaskDetailView: View {
    @ObservedObject var viewModel: AISettingsViewModel
    let taskCode: String
    let source: TaskSource

    @State private var editingTask: SmallTask?

    private var task: SmallTask? {
        viewModel.effectiveSmallTasks.first { $0.code == taskCode && $0.source == source }
            ?? viewModel.snapshot.smallTasks.first { $0.code == taskCode && $0.source == source }
    }

    var body: some View {
        Group {
            if let task {
                Form {
                    overviewSection(task)
                    metadataSection(task)
                    toolsSection(task)
                    promptSection(task)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(
                        L10n.text(
                            "ai_settings.small_tasks.detail.not_found",
                            fallback: "Small task not found",
                            comment: "Small task detail missing task"
                        )
                    )
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(
            L10n.text(
                "ai_settings.small_tasks.detail.title",
                fallback: "Small task detail",
                comment: "Small task detail title"
            )
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let task, task.source == .local {
                    Button(
                        L10n.text("common.edit", fallback: "Edit", comment: "Edit action")
                    ) {
                        editingTask = task
                    }
                }
            }
        }
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
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshEffectiveSmallTasks()
        }
    }

    private func overviewSection(_ task: SmallTask) -> some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: task.icon.isEmpty ? "checklist" : task.icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(task.source == .local ? .blue : .purple)
                    .frame(width: 48, height: 48)
                    .background((task.source == .local ? Color.blue : Color.purple).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(task.name.isEmpty ? task.code : task.name)
                            .font(.headline)

                        Text(task.source.localizedSmallTaskTitle)
                            .font(.caption2)
                            .foregroundStyle(task.source == .local ? .blue : .purple)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background((task.source == .local ? Color.blue : Color.purple).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(task.brief.isEmpty ? task.code : task.brief)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func metadataSection(_ task: SmallTask) -> some View {
        Section(
            L10n.text(
                "ai_settings.small_tasks.detail.section.metadata",
                fallback: "Metadata",
                comment: "Small task metadata section"
            )
        ) {
            SmallTaskDetailRow(
                title: L10n.text(
                    "ai_settings.small_tasks.detail.source",
                    fallback: "Source",
                    comment: "Small task source label"
                ),
                value: task.source.localizedSmallTaskTitle
            )
            SmallTaskDetailRow(
                title: L10n.text(
                    "ai_settings.small_tasks.detail.code",
                    fallback: "Code",
                    comment: "Small task code label"
                ),
                value: task.code
            )
            if let versionDisplay = viewModel.smallTaskVersionDisplay(for: task) {
                SmallTaskDetailRow(
                    title: L10n.text(
                        "ai_settings.small_tasks.detail.version",
                        fallback: "Current version",
                        comment: "Small task version label"
                    ),
                    value: versionDisplay.localizedText
                )
            }
            SmallTaskDetailRow(
                title: L10n.text(
                    "ai_settings.small_tasks.detail.tools_count",
                    fallback: "Tools",
                    comment: "Small task tools count label"
                ),
                value: "\(task.toolList.count)"
            )
        }
    }

    private func toolsSection(_ task: SmallTask) -> some View {
        Section(
            L10n.text(
                "ai_settings.small_tasks.detail.tools",
                fallback: "Tools",
                comment: "Small task tools section"
            )
        ) {
            if task.toolList.isEmpty {
                Text(
                    L10n.text(
                        "ai_settings.small_tasks.detail.tools.empty",
                        fallback: "None",
                        comment: "No small task tools"
                    )
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(task.toolList, id: \.self) { tool in
                    NavigationLink {
                        AIToolDetailDestinationView(toolName: tool, viewModel: viewModel)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AIToolCatalog.displayTitle(for: tool))
                                .foregroundStyle(.primary)
                            Text(tool)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func promptSection(_ task: SmallTask) -> some View {
        Section(
            L10n.text(
                "ai_settings.small_tasks.detail.prompt",
                fallback: "Prompt",
                comment: "Small task prompt section"
            )
        ) {
            Text(task.prompt.isEmpty ? "-" : task.prompt)
                .font(.footnote)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SmallTaskDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private extension TaskSource {
    var localizedSmallTaskTitle: String {
        switch self {
        case .local:
            return L10n.text("ai_settings.small_tasks.source.local", fallback: "Local", comment: "Local small task source")
        case .service:
            return L10n.text("ai_settings.small_tasks.source.service", fallback: "Service", comment: "Service small task source")
        }
    }
}

private extension SmallTaskVersionDisplay {
    var localizedText: String {
        switch self {
        case .version(let version):
            return L10n.format(
                "ai_settings.small_tasks.detail.version.format",
                fallback: "v%d",
                comment: "Small task version display format",
                version
            )
        case .localCustom:
            return L10n.text(
                "ai_settings.small_tasks.detail.version.custom",
                fallback: "Local custom",
                comment: "Local custom small task version"
            )
        case .unversioned:
            return L10n.text(
                "ai_settings.small_tasks.detail.version.unversioned",
                fallback: "Unversioned",
                comment: "Unversioned small task"
            )
        }
    }
}
