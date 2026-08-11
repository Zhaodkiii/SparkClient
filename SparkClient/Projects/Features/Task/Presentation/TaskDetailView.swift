import SwiftUI

struct TaskDetailView: View {
    let memberID: Int?
    @ObservedObject var taskManager: TaskManager
    let knowledgeDependencies: KnowledgeFeatureDependencies
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @State private var currentMode: TaskDetailMode
    @State private var previewCard: TaskCard?
    @State private var previewSaveState: TaskPreviewSaveState = .idle

    @State private var showEdit = false
    @State private var showPreviewEdit = false
    @State private var showRepeatEditSheet = false
    @State private var pendingEditScope: TaskRepeatEditScope = .instance
    @State private var showCancelConfirm = false
    @State private var actionError: String?
    @State private var relatedKnowledgeDocument: KnowledgeDocument?
    @State private var isLoadingRelatedBusiness = false
    @State private var pendingKnowledgeOpen: PendingKnowledgeOpen?
    let onPreviewSave: ((TaskCardPreviewContext, TaskCard) async throws -> HealthTask)?
    let onPreviewEdit: ((TaskCardPreviewContext, TaskCardPreviewEditResult) async -> Void)?

    private var task: HealthTask? {
        guard let taskID = currentMode.taskID else { return nil }
        return taskManager.task(for: taskID)
    }

    private var detailModel: TaskDetailModel? {
        task.map { TaskDetailModelBuilder.make(task: $0) }
    }

    private var previewContext: TaskCardPreviewContext? {
        currentMode.previewContext
    }

    private var previewTaskCard: TaskCard? {
        previewCard ?? previewContext?.card
    }

    private var previewModel: TaskDetailPreviewModel? {
        previewTaskCard.map { TaskCardPreviewMapper.makeDisplayModel(from: $0) }
    }

    private var isPreviewMode: Bool {
        currentMode.isPreview
    }

    init(
        memberID: Int?,
        taskManager: TaskManager,
        knowledgeDependencies: KnowledgeFeatureDependencies,
        knowledgeViewModel: KnowledgeLibraryViewModel,
        taskID: Int
    ) {
        self.memberID = memberID
        self._taskManager = ObservedObject(wrappedValue: taskManager)
        self.knowledgeDependencies = knowledgeDependencies
        self._knowledgeViewModel = ObservedObject(wrappedValue: knowledgeViewModel)
        self._currentMode = State(initialValue: .normal(taskID: taskID))
        self._previewCard = State(initialValue: nil)
        self.onPreviewSave = nil
        self.onPreviewEdit = nil
    }

    init(
        memberID: Int?,
        taskManager: TaskManager,
        knowledgeDependencies: KnowledgeFeatureDependencies,
        knowledgeViewModel: KnowledgeLibraryViewModel,
        mode: TaskDetailMode,
        onPreviewSave: ((TaskCardPreviewContext, TaskCard) async throws -> HealthTask)? = nil,
        onPreviewEdit: ((TaskCardPreviewContext, TaskCardPreviewEditResult) async -> Void)? = nil
    ) {
        self.memberID = memberID
        self._taskManager = ObservedObject(wrappedValue: taskManager)
        self.knowledgeDependencies = knowledgeDependencies
        self._knowledgeViewModel = ObservedObject(wrappedValue: knowledgeViewModel)
        self._currentMode = State(initialValue: mode)
        self._previewCard = State(initialValue: mode.previewContext?.card)
        self.onPreviewSave = onPreviewSave
        self.onPreviewEdit = onPreviewEdit
    }

    var body: some View {
        mainContent
        .navigationTitle(isPreviewMode
                         ? NSLocalizedString("task.preview.title", comment: "任务预览")
                         : NSLocalizedString("task.detail.title", comment: "任务详情"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pendingKnowledgeOpen) { pending in
            KnowledgeDocumentDetailView(
                dependencies: knowledgeDependencies,
                viewModel: knowledgeViewModel,
                documentID: pending.documentID
            )
            .hidesMainTabBarWhenPushed()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                toolbarMenu
            }
        }
        .task {
            if let taskID = currentMode.taskID {
                await taskManager.loadExecutions(taskID: taskID)
            }
        }
        .task(id: task?.businessID ?? "") {
            if isPreviewMode == false {
                await loadRelatedBusinessPreview()
            }
        }
        .sheet(isPresented: $showEdit) {
            if let taskID = currentMode.taskID {
                CompatibleNavigationContainer {
                    TaskCreateView(
                        memberID: memberID,
                        taskManager: taskManager,
                        mode: .edit(taskID: taskID, scope: pendingEditScope),
                        onDismiss: { showEdit = false }
                    )
                }
            }
        }
        .sheet(isPresented: $showPreviewEdit) {
            if let previewTaskCard, let previewContext {
                CompatibleNavigationContainer {
                    TaskCreateView(
                        memberID: previewTaskCard.member,
                        taskManager: taskManager,
                        mode: .previewEdit(initialDraft: TaskCreateFormDraft.from(card: previewTaskCard)),
                        onDismiss: { showPreviewEdit = false },
                        onPreviewSaveDraft: { draft in
                            let updatedCard = TaskCardPreviewMapper.applying(draft, to: previewTaskCard)
                            previewCard = updatedCard
                            if let onPreviewEdit {
                                Task {
                                    await onPreviewEdit(
                                        previewContext,
                                        TaskCardPreviewEditResult(draft: draft, updatedAt: Date())
                                    )
                                }
                            }
                        }
                    )
                }
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
                    guard let taskID = currentMode.taskID else { return }
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

    private var mainContent: AnyView {
        if isPreviewMode {
            if let previewTaskCard, let previewModel {
                return AnyView(previewDetailContent(card: previewTaskCard, model: previewModel))
            }
            return AnyView(ProgressView())
        }

        if let task, let detailModel {
            return AnyView(normalDetailContent(task: task, detailModel: detailModel))
        }

        return AnyView(ProgressView())
    }

    private func headerSection(task: HealthTask, detailModel: TaskDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    if task.description.isEmpty == false {
                        Text(task.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: task.type.iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(task.type.accentColor)
                    .frame(width: 40, height: 40)
                    .background(task.type.backgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 8) {
                statusBadge(for: task.status, overdue: detailModel.overdue)
                TaskPriorityBadge(priority: task.priority)
                TaskTypeBadge(type: task.type)
            }
        }
    }

    private func basicInfoCard(task: HealthTask, detailModel: TaskDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("task.section.basic", comment: "基本信息"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            detailRow(NSLocalizedString("task.field.time", comment: "时间"), TaskDateHelper.relativeTimeLabel(task))
            detailRow(NSLocalizedString("task.field.repeat", comment: "重复"), task.repeatType.displayName)
            detailRow(NSLocalizedString("task.field.source", comment: "来源"), task.source.displayName)
            detailRow(NSLocalizedString("task.field.business_type", comment: "关联业务类型"), task.businessType.taskBusinessTypeDisplayName)

            if let reminder = reminderText(for: task) {
                detailRow(NSLocalizedString("task.field.reminder_time", comment: "提醒时间"), reminder)
            }

            if detailModel.overdue {
                detailRow(
                    NSLocalizedString("task.field.status", comment: "状态"),
                    NSLocalizedString("task.status.overdue_pending", comment: "已过期 / 待处理"),
                    valueColor: Color(uiColor: .systemRed)
                )
            } else {
                detailRow(
                    NSLocalizedString("task.field.status", comment: "状态"),
                    task.status.displayName
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func relatedBusinessSection(task: HealthTask) -> some View {
        let normalizedType = normalizedBusinessType(task.businessType)
        if normalizedType.isEmpty == false {
            TaskRelatedBusinessCardView(
                businessTypeName: task.businessType.taskBusinessTypeDisplayName,
                businessID: task.businessID,
                taskDescription: task.description,
                contentState: relatedBusinessContentState(for: normalizedType),
                onOpen: openAction(for: normalizedType)
            )
        }
    }

    @ViewBuilder
    private func executionHistorySection(task: HealthTask) -> some View {
        let records = taskManager.executions(for: task.id)
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("task.detail.executions", comment: "最近执行记录"))
                .font(.subheadline.weight(.semibold))

            if records.isEmpty {
                Text(NSLocalizedString("task.detail.no_executions", comment: "暂无执行记录"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(records.prefix(10)) { record in
                        HStack(spacing: 10) {
                            Text(record.status.displayName)
                                .font(.caption.bold())
                                .foregroundStyle(executionColor(record.status))
                                .frame(width: 44, alignment: .leading)
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
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
        }
    }

    private func statusBadge(for status: HealthTask.TaskStatus, overdue: Bool) -> some View {
        Text(overdue
            ? NSLocalizedString("task.status.overdue", comment: "已过期")
            : status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusBadgeBackground(status: status, overdue: overdue), in: Capsule())
            .foregroundStyle(statusBadgeForeground(status: status, overdue: overdue))
    }

    private func statusBadgeForeground(status: HealthTask.TaskStatus, overdue: Bool) -> Color {
        if overdue {
            return Color(uiColor: .systemRed)
        }
        switch status {
        case .pending:
            return Color(uiColor: .systemOrange)
        case .completed:
            return Color(uiColor: .systemGreen)
        case .canceled:
            return Color(uiColor: .secondaryLabel)
        }
    }

    private func statusBadgeBackground(status: HealthTask.TaskStatus, overdue: Bool) -> Color {
        if overdue {
            return Color(uiColor: .systemRed).opacity(0.12)
        }
        switch status {
        case .pending:
            return Color(uiColor: .systemOrange).opacity(0.14)
        case .completed:
            return Color(uiColor: .systemGreen).opacity(0.14)
        case .canceled:
            return Color(uiColor: .tertiarySystemFill)
        }
    }

    private func reminderText(for task: HealthTask) -> String? {
        guard let reminder = task.taskMedical?.reminderTime else { return nil }
        return DateFormatter.localizedString(from: reminder, dateStyle: .none, timeStyle: .short)
    }

    private func detailRow(_ title: String, _ value: String, valueColor: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Spacer(minLength: 0)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private func previewHeaderSection(card: TaskCard, model: TaskDetailPreviewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    if model.description.isEmpty == false {
                        Text(model.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: card.type.iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(card.type.accentColor)
                    .frame(width: 40, height: 40)
                    .background(card.type.backgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 8) {
                previewBadge(model.statusText, tint: .blue)
                previewBadge(model.priorityText, tint: card.priority == .high ? .red : (card.priority == .medium ? .orange : .secondary))
                previewBadge(card.type.displayName, tint: card.type.accentColor)
            }
        }
    }

    private func previewBasicInfoCard(card: TaskCard, model: TaskDetailPreviewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("task.section.basic", comment: "基本信息"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            detailRow(NSLocalizedString("task.field.time", comment: "时间"), model.startTimeText ?? NSLocalizedString("task.time.unspecified", comment: "未设置时间"))
            detailRow(NSLocalizedString("task.field.repeat", comment: "重复"), model.repeatText)
            detailRow(NSLocalizedString("task.field.source", comment: "来源"), model.sourceText)
            detailRow(NSLocalizedString("task.field.business_type", comment: "关联业务类型"), model.businessTypeText)
            detailRow(NSLocalizedString("task.field.business_id", comment: "业务 ID"), model.businessIDText)

            if let due = model.dueTimeText {
                detailRow(NSLocalizedString("task.field.due_time", comment: "截止时间"), due)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
        )
    }

    private func previewDetailContent(card: TaskCard, model: TaskDetailPreviewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                previewHeaderSection(card: card, model: model)
                previewBasicInfoCard(card: card, model: model)
                previewBusinessPanel(model: model)
            }
            .padding(16)
            .padding(.bottom, 92)
        }
        .safeAreaInset(edge: .bottom) {
            previewSaveBar
        }
    }

    @ViewBuilder
    private var toolbarMenu: some View {
        if isPreviewMode {
            Menu {
                Button(NSLocalizedString("task.preview.edit", comment: "本地修改")) {
                    showPreviewEdit = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        } else if detailModel?.canEdit == true {
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

    private func normalDetailContent(task: HealthTask, detailModel: TaskDetailModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(task: task, detailModel: detailModel)
                basicInfoCard(task: task, detailModel: detailModel)
                TaskBusinessPanelView(task: task)
                relatedBusinessSection(task: task)
                executionHistorySection(task: task)
            }
            .padding(16)
            .padding(.bottom, detailModel.canExecute ? 88 : 16)
        }
        .safeAreaInset(edge: .bottom) {
            if detailModel.canExecute {
                TaskDetailBottomActionBar(
                    isSubmitting: taskManager.isSubmittingExecution,
                    onDone: { submitExecution(status: .done) },
                    onSkip: { submitExecution(status: .skipped) },
                    onFail: { submitExecution(status: .failed) }
                )
            }
        }
    }

    @ViewBuilder
    private var previewSaveBar: some View {
        TaskPreviewSaveBottomBar(isSaving: previewSaveState.isSaving) {
            Task { await savePreviewTask() }
        }
    }

    private func previewBusinessPanel(model: TaskDetailPreviewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.type.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(model.type.accentColor)

            if model.businessRows.isEmpty {
                Text(NSLocalizedString("task.detail.business_unavailable", comment: "业务信息暂不可用"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.businessRows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(row.value)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(model.type.accentColor.opacity(0.12), lineWidth: 1)
        )
    }

    private func previewBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
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

    @MainActor
    private func savePreviewTask() async {
        guard let previewContext, let previewTaskCard else { return }
        guard let onPreviewSave else {
            actionError = NSLocalizedString("task.preview.save_failed", comment: "保存失败")
            return
        }
        guard previewSaveState.isSaving == false else { return }
        previewSaveState = .saving
        do {
            let createdTask = try await onPreviewSave(previewContext, previewTaskCard)
            previewSaveState = .saved(taskID: createdTask.id)
            currentMode = .normal(taskID: createdTask.id)
            previewCard = nil
            await taskManager.loadExecutions(taskID: createdTask.id)
        } catch {
            previewSaveState = .failed(message: error.localizedDescription)
            actionError = error.localizedDescription
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

    private func loadRelatedBusinessPreview() async {
        guard let task else {
            relatedKnowledgeDocument = nil
            return
        }

        let normalizedType = normalizedBusinessType(task.businessType)
        guard normalizedType == "knowledge" else {
            relatedKnowledgeDocument = nil
            return
        }

        guard let documentID = UUID(uuidString: task.businessID) else {
            relatedKnowledgeDocument = nil
            return
        }

        isLoadingRelatedBusiness = true
        defer { isLoadingRelatedBusiness = false }
        relatedKnowledgeDocument = await knowledgeViewModel.loadDocument(id: documentID)
    }

    private func relatedBusinessContentState(for normalizedType: String) -> TaskRelatedBusinessCardView.ContentState {
        switch normalizedType {
        case "knowledge":
            if isLoadingRelatedBusiness {
                return .loading
            }
            if let document = relatedKnowledgeDocument {
                return .knowledge(document: document)
            }
            return .unavailable(message: NSLocalizedString("task.related.not_found", comment: "未找到关联内容"))
        default:
            return .unsupported
        }
    }

    private func openAction(for normalizedType: String) -> (() -> Void)? {
        guard normalizedType == "knowledge", let document = relatedKnowledgeDocument else {
            return nil
        }
        return {
            pendingKnowledgeOpen = PendingKnowledgeOpen(documentID: document.id)
        }
    }

    private func normalizedBusinessType(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func executionColor(_ status: TaskExecutionStatus) -> Color {
        switch status {
        case .done:
            return .green
        case .skipped:
            return Color(uiColor: .systemTeal)
        case .failed:
            return .red
        }
    }
}

private struct PendingKnowledgeOpen: Identifiable, Equatable, Hashable {
    let documentID: UUID

    var id: UUID { documentID }
}

private enum TaskPreviewSaveState: Equatable {
    case idle
    case saving
    case saved(taskID: Int)
    case failed(message: String)

    var isSaving: Bool {
        if case .saving = self { return true }
        return false
    }
}
