import SwiftUI

struct TaskCreateView: View {
    enum Mode {
        case create
        case edit(taskID: Int, scope: TaskRepeatEditScope)
        case previewEdit(initialDraft: TaskCreateFormDraft)
    }

    enum CreationTab: String, CaseIterable, Identifiable {
        case manual
        case ai

        var id: String { rawValue }

        var title: String {
            switch self {
            case .manual:
                return NSLocalizedString("task.create.manual", comment: "手动创建")
            case .ai:
                return NSLocalizedString("task.create.ai", comment: "AI 生成")
            }
        }
    }

    let memberID: Int?
    @ObservedObject var taskManager: TaskManager
    let mode: Mode
    let onDismiss: () -> Void
    let onPreviewSaveDraft: ((TaskCreateFormDraft) -> Void)?

    @State private var tab: CreationTab = .manual
    @State private var draft = TaskCreateFormDraft()
    @State private var aiJSONText = ""
    @State private var aiError: String?
    @State private var isSaving = false
    @State private var saveError: String?

    init(
        memberID: Int?,
        taskManager: TaskManager,
        mode: Mode,
        onDismiss: @escaping () -> Void,
        onPreviewSaveDraft: ((TaskCreateFormDraft) -> Void)? = nil
    ) {
        self.memberID = memberID
        self._taskManager = ObservedObject(wrappedValue: taskManager)
        self.mode = mode
        self.onDismiss = onDismiss
        self.onPreviewSaveDraft = onPreviewSaveDraft
    }

    private var isEditMode: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isPreviewEditMode: Bool {
        if case .previewEdit = mode { return true }
        return false
    }

    private var isFixedManualMode: Bool {
        isEditMode || isPreviewEditMode
    }

    var body: some View {
        Form {
            if isFixedManualMode == false {
                Section {
                    Picker("task_create_mode", selection: $tab) {
                        ForEach(CreationTab.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if tab == .ai && isFixedManualMode == false {
                aiSection
            } else {
                manualSection
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("common.cancel", comment: "取消"), action: onDismiss)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("common.save", comment: "保存")) {
                    Task { await save() }
                }
                .disabled(isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear(perform: loadEditDraftIfNeeded)
        .alert(
            NSLocalizedString("common.error", comment: "Error"),
            isPresented: Binding(
                get: { saveError != nil },
                set: { if $0 == false { saveError = nil } }
            )
        ) {
            Button(NSLocalizedString("common.ok", comment: "OK"), role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .create:
            return NSLocalizedString("task.create.title", comment: "创建任务")
        case .edit:
            return NSLocalizedString("task.edit.title", comment: "修改任务")
        case .previewEdit:
            return NSLocalizedString("task.preview.edit_title", comment: "修改任务草稿")
        }
    }

    @ViewBuilder
    private var manualSection: some View {
        Section {
            TextField(NSLocalizedString("common.title", comment: "Title"), text: $draft.title)
            TextField(NSLocalizedString("task.field.description", comment: "描述"), text: $draft.description, axis: .vertical)
                .lineLimit(3...6)
        }

        Section(NSLocalizedString("task.section.basic", comment: "基本信息")) {
            Picker(NSLocalizedString("task.field.type", comment: "类型"), selection: $draft.type) {
                ForEach(HealthTask.TaskType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            DatePicker(NSLocalizedString("task.field.start_time", comment: "开始时间"), selection: $draft.startTime)
            DatePicker(NSLocalizedString("task.field.due_time", comment: "截止时间"), selection: $draft.dueTime)
            Picker(NSLocalizedString("task.field.repeat", comment: "重复"), selection: $draft.repeatType) {
                Text(HealthTask.RepeatType.none.displayName).tag(HealthTask.RepeatType.none)
                Text(HealthTask.RepeatType.daily.displayName).tag(HealthTask.RepeatType.daily)
                Text(HealthTask.RepeatType.weekly.displayName).tag(HealthTask.RepeatType.weekly)
            }
            Picker(NSLocalizedString("task.field.priority", comment: "优先级"), selection: $draft.priority) {
                Text(HealthTask.Priority.high.displayName).tag(HealthTask.Priority.high)
                Text(HealthTask.Priority.medium.displayName).tag(HealthTask.Priority.medium)
                Text(HealthTask.Priority.low.displayName).tag(HealthTask.Priority.low)
            }
        }

        businessSection
    }

    @ViewBuilder
    private var businessSection: some View {
        switch draft.type {
        case .medical:
            Section(NSLocalizedString("task.panel.medical", comment: "医疗面板")) {
                DatePicker(NSLocalizedString("task.field.reminder_time", comment: "提醒时间"), selection: $draft.medicalReminderTime)
                TextField(NSLocalizedString("task.field.medical_type", comment: "医疗任务类型"), text: $draft.medicalTaskType)
            }
        case .exercise:
            Section(NSLocalizedString("task.panel.exercise", comment: "运动面板")) {
                TextField(NSLocalizedString("task.field.exercise_type", comment: "运动类型"), text: $draft.exerciseType)
                Stepper(
                    String(format: NSLocalizedString("task.field.duration_minutes", comment: "%d 分钟"), draft.exerciseDurationMin),
                    value: $draft.exerciseDurationMin,
                    in: 5...240,
                    step: 5
                )
                TextField(NSLocalizedString("task.field.intensity", comment: "强度"), text: $draft.exerciseIntensity)
            }
        case .diet:
            Section(NSLocalizedString("task.panel.diet", comment: "饮食面板")) {
                TextField(NSLocalizedString("task.field.meal_type", comment: "餐次类型"), text: $draft.dietMealType)
                Stepper(
                    String(format: NSLocalizedString("task.detail.diet_calories", comment: "%d kcal"), draft.dietCalorieTarget),
                    value: $draft.dietCalorieTarget,
                    in: 100...3000,
                    step: 50
                )
                TextField(NSLocalizedString("task.field.food_recommend", comment: "食物推荐"), text: $draft.dietFoodRecommend, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }

    @ViewBuilder
    private var aiSection: some View {
        Section(NSLocalizedString("task.create.ai_input", comment: "粘贴 AI 结构化 JSON")) {
            TextEditor(text: $aiJSONText)
                .frame(minHeight: 180)
                .font(.system(.footnote, design: .monospaced))

            Button(NSLocalizedString("task.create.ai_parse", comment: "解析并填充")) {
                parseAIJSON()
            }
        }

        if let aiError {
            Section {
                Text(aiError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private func loadEditDraftIfNeeded() {
        switch mode {
        case .create:
            break
        case .edit(let taskID, _):
            guard let task = taskManager.task(for: taskID) else { return }
            draft = TaskCreateFormDraft.from(task: task)
            tab = .manual
        case .previewEdit(let initialDraft):
            draft = initialDraft
            tab = .manual
        }
    }

    private func parseAIJSON() {
        do {
            let parsed = try TaskAITaskDraftParser.parse(jsonText: aiJSONText)
            draft = parsed.form
            aiError = nil
            tab = .manual
        } catch {
            aiError = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            switch mode {
            case .create:
                guard let memberID else {
                    saveError = NSLocalizedString("task.error.member_required", comment: "请先选择成员")
                    return
                }
                try await taskManager.createTask(payload: draft.makeCreatePayload(memberID: memberID))
            case .edit(let taskID, let scope):
                try await taskManager.updateTask(taskID: taskID, payload: draft.makeUpdatePayload(), scope: scope)
            case .previewEdit:
                onPreviewSaveDraft?(draft)
            }
            onDismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
