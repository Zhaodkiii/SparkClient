import SwiftUI

private enum MedicationFilterType: String, Identifiable, CaseIterable {
    case active
    case notStarted
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active:
            return L10n.text("home.medical.list.medications.filter.active", fallback: "执行中")
        case .notStarted:
            return L10n.text("home.medical.list.medications.filter.not_started", fallback: "未开始")
        case .completed:
            return L10n.text("home.medical.list.medications.filter.completed", fallback: "已完成")
        }
    }
}

struct MedicationsListPage: View {
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let workflowAPI: SparkMedicalWorkflowAPI
    @ObservedObject var memberContextStore: MemberContextStore

    @State private var selectedFilter: MedicationFilterType = .active
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var medicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    @State private var sheetDestination: MedicationPlanSheetDestination?

    private let logger: Logger = ConsoleLogger()
    private let logModule = LogModule.home

    init(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        workflowAPI: SparkMedicalWorkflowAPI,
        memberContextStore: MemberContextStore
    ) {
        self.completeData = completeData
        self.workflowAPI = workflowAPI
        self.memberContextStore = memberContextStore
        _medicineBoxes = State(initialValue: completeData?.medicineBoxes ?? [])
        _medicationPlans = State(initialValue: completeData?.medicationPlans ?? [])
    }

    private var memberID: Int? {
        completeData?.memberId ?? memberContextStore.context.selectedMember?.id
    }

    private var medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox] {
        Dictionary(uniqueKeysWithValues: medicineBoxes.map { ($0.id, $0) })
    }

    private var recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]] {
        Dictionary(grouping: completeData?.todayMedicationRecords ?? [], by: \.plan)
    }

    private var sortedPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan] {
        medicationPlans.sorted { lhs, rhs in
            if lhs.status == rhs.status {
                return lhs.startDate > rhs.startDate
            }
            return statusRank(lhs.status) < statusRank(rhs.status)
        }
    }

    private var filteredPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan] {
        sortedPlans.filter { plan in
            switch selectedFilter {
            case .active:
                return plan.status == "active" && isPlanInDateRange(plan)
            case .notStarted:
                return plan.status == "paused" || plan.startDate > today
            case .completed:
                return plan.status == "completed" || plan.status == "cancelled" || isPlanEnded(plan)
            }
        }
    }

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            filterTabBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if filteredPlans.isEmpty {
                emptyStateView
            } else {
                medicationListContent
            }
        }
        .overlay(bottomActionBar, alignment: .bottom)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.medical.list.medications.title", fallback: "服药计划"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    MedicineBoxListPage(
                        medicineBoxes: medicineBoxes,
                        memberID: memberID,
                        workflowAPI: workflowAPI,
                        onMedicineBoxesChanged: { medicineBoxes = $0 }
                    )
                } label: {
                    Label("药箱", systemImage: "pills.fill")
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .onAppear {
            logger.info(
                "打开服药计划列表 filter=\(selectedFilter.rawValue) total=\(sortedPlans.count) filtered=\(filteredPlans.count)",
                module: logModule
            )
        }
        .onChange(of: selectedFilter) { newValue in
            logger.info(
                "切换服药计划筛选 filter=\(newValue.rawValue) filtered=\(filteredPlans.count)",
                module: logModule
            )
        }
        .onChange(of: completeData?.medicineBoxes ?? []) { newValue in
            medicineBoxes = newValue
        }
        .onChange(of: completeData?.medicationPlans ?? []) { newValue in
            medicationPlans = newValue
        }
        .sheet(item: $sheetDestination) { destination in
            if let memberID {
                MedicationPlanFormView(
                    mode: destination.formMode,
                    memberID: memberID,
                    medicineBoxes: medicineBoxes,
                    workflowAPI: workflowAPI,
                    onMedicineBoxSaved: upsertMedicineBox,
                    onServerSaved: upsertMedicationPlan
                )
            } else {
                Text("请先选择成员")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var filterTabBar: some View {
        HStack(spacing: 0) {
            ForEach(MedicationFilterType.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    VStack(spacing: 8) {
                        Text(filter.title)
                            .font(selectedFilter == filter ? .subheadline.weight(.semibold) : .subheadline)
                            .foregroundStyle(
                                selectedFilter == filter
                                ? Color(uiColor: .systemBlue)
                                : Color(uiColor: .systemBlue).opacity(0.6)
                            )

                        Rectangle()
                            .fill(selectedFilter == filter ? Color(uiColor: .systemBlue) : Color.clear)
                            .frame(height: 2)
                            .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedFilter)
    }

    private var medicationListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredPlans, id: \.id) { plan in
                    NavigationLink {
                        MedicationPlanDetailPage(
                            plan: plan,
                            medicineBoxes: medicineBoxes,
                            records: recordsByPlanID[plan.id] ?? [],
                            memberID: memberID,
                            workflowAPI: workflowAPI,
                            onSaved: upsertMedicationPlan,
                            onDeleted: removeMedicationPlan,
                            onMedicineBoxSaved: upsertMedicineBox
                        )
                    } label: {
                        MedicationPlanCard(
                            plan: plan,
                            medicineBox: plan.medicineBox.flatMap { medicineBoxesByID[$0] },
                            records: recordsByPlanID[plan.id] ?? []
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                Text(L10n.text("home.medical.list.medications.footer.no_more", fallback: "没有更多了"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.bottom, 96)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(L10n.text("home.medical.list.medications.empty.title", fallback: "暂无服药计划"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(L10n.text("home.medical.list.medications.empty.subtitle", fallback: "创建服药计划后，可按时间、剂量和频次跟踪。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color(uiColor: .separator).opacity(0.2))

            VStack(spacing: 12) {
                Button {
                    sheetDestination = .create
                } label: {
                    Text(L10n.text("home.medical.list.medications.action.add_plan", fallback: "新增服药计划"))
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Color(uiColor: .systemPurple),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(memberID == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private func upsertMedicationPlan(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) {
        if let index = medicationPlans.firstIndex(where: { $0.id == plan.id }) {
            medicationPlans[index] = plan
        } else {
            medicationPlans.insert(plan, at: 0)
        }
        sheetDestination = nil
    }

    private func removeMedicationPlan(id: Int) {
        medicationPlans.removeAll { $0.id == id }
    }

    private func upsertMedicineBox(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
            medicineBoxes[index] = box
        } else {
            medicineBoxes.insert(box, at: 0)
        }
    }

    private func statusRank(_ status: String) -> Int {
        switch status {
        case "active":
            return 0
        case "paused":
            return 1
        case "completed":
            return 2
        case "cancelled":
            return 3
        default:
            return 4
        }
    }

    private func isPlanInDateRange(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> Bool {
        plan.startDate <= today && isPlanEnded(plan) == false
    }

    private func isPlanEnded(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> Bool {
        guard let endDate = plan.endDate else {
            return false
        }
        return endDate < today
    }
}

private enum MedicationPlanSheetDestination: Identifiable {
    case create
    case serverEdit(SparkMedicalSyncAPI.RemoteMedicationPlan)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .serverEdit(let plan):
            return "server_\(plan.id)"
        }
    }

    var formMode: MedicationPlanFormView.Mode {
        switch self {
        case .create:
            return .create
        case .serverEdit(let plan):
            return .serverEdit(existing: plan)
        }
    }
}

struct MedicationPlanFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: SparkMedicalSyncAPI.RemoteMedicationPlan)
        case localEdit(existing: MedicationPlanDraft, onSubmit: (MedicationPlanDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let memberID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let onMedicineBoxSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    let onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void)?

    @State private var draft: MedicationPlanDraft
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @State private var sheetKeyboardVisible = false

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    init(
        mode: Mode,
        memberID: Int,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        workflowAPI: SparkMedicalWorkflowAPI,
        onMedicineBoxSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void)? = nil
    ) {
        self.mode = mode
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.onMedicineBoxSaved = onMedicineBoxSaved
        self.onServerSaved = onServerSaved
        _medicineBoxes = State(initialValue: medicineBoxes)

        switch mode {
        case .create:
            _draft = State(initialValue: MedicationPlanDraft())
        case .serverEdit(let existing):
            _draft = State(initialValue: MedicationPlanDraft(existing: existing))
        case .localEdit(let existing, _):
            _draft = State(initialValue: existing)
        }
    }

    private var selectedMedicineBox: SparkMedicalSyncAPI.RemoteMedicineBox? {
        guard let medicineBoxID = draft.medicineBoxID else { return nil }
        return medicineBoxes.first(where: { $0.id == medicineBoxID })
    }

    private var canSubmit: Bool {
        isSubmitting == false
        && draft.drugName.nilIfBlank != nil
        && draft.dosePerTime.nilIfBlank != nil
        && draft.frequencyText.nilIfBlank != nil
        && draft.reminderTimesError == nil
        && draft.durationDaysValue != nil
        && (draft.hasEndDate == false || draft.endDate >= draft.startDate)
    }

    private var navigationTitle: String {
        switch mode {
        case .create:
            return "新增服药计划"
        case .serverEdit, .localEdit:
            return "编辑服药计划"
        }
    }

    var body: some View {
        NavigationView {
            formContent
                .sparkKeyboardDoneToolbar {
                    SparkKeyboardDismiss.endEditing()
                }
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .background(Color(uiColor: .systemGroupedBackground))
                .sparkFormBottomBar(
                    canSubmit: canSubmit,
                    cancelTitle: L10n.text("common.cancel"),
                    saveTitle: L10n.text("common.done"),
                    saveSystemImage: "checkmark.circle.fill",
                    keyboardVisible: $sheetKeyboardVisible,
                    onCancel: {
                        formLog.info("MedicationPlanFormView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
                        dismiss()
                    },
                    onSave: {
                        guard canSubmit else { return }
                        submitDraft()
                    }
                )
        }
        .interactiveDismissDisabled(isSubmitting)
        .alert("保存失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                SparkFormCard(title: "关联药品", titleSystemImage: "pills.fill") {
                    NavigationLink {
                        MedicationPlanMedicineBoxPickerPage(
                            memberID: memberID,
                            medicineBoxes: medicineBoxes,
                            selectedMedicineBoxID: draft.medicineBoxID,
                            workflowAPI: workflowAPI,
                            onMedicineBoxSaved: handleMedicineBoxSaved,
                            onSelect: applyMedicineBoxSelection
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox.fill")
                                .font(.headline)
                                .foregroundStyle(Color(uiColor: .systemPurple))
                                .frame(width: 36, height: 36)
                                .background(Color(uiColor: .systemPurple).opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(selectedMedicineBoxTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(selectedMedicineBoxSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 56)
                        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                SparkFormCard(title: "用药规则", titleSystemImage: "calendar.badge.clock") {
                    VStack(spacing: 12) {
                        SparkFormTextRow(title: "药品名称", text: $draft.drugName, placeholder: "如 阿莫西林胶囊", required: true, keyboardVisible: $sheetKeyboardVisible)
                        SparkFormTextRow(title: "单次剂量", text: $draft.dosePerTime, placeholder: "如 1片 / 5ml", required: true, keyboardVisible: $sheetKeyboardVisible)
                        HStack(spacing: 12) {
                            SparkFormTextRow(title: "剂量数值", text: $draft.doseValue, placeholder: "如 1", keyboardVisible: $sheetKeyboardVisible)
                                .keyboardType(.decimalPad)
                            SparkFormTextRow(title: "单位", text: $draft.doseUnit, placeholder: "片", keyboardVisible: $sheetKeyboardVisible)
                        }
                        SparkFormTextRow(title: "频次", text: $draft.frequencyText, placeholder: "如 每日3次", required: true, keyboardVisible: $sheetKeyboardVisible)
                        SparkFormTextRow(title: "频次编码", text: $draft.frequencyCode, placeholder: "可选，如 tid", keyboardVisible: $sheetKeyboardVisible)
                        SparkFormTextRow(title: "提醒时间", text: $draft.reminderTimesText, placeholder: "如 08:00, 12:00, 20:00", keyboardVisible: $sheetKeyboardVisible)
                        if let reminderTimesError = draft.reminderTimesError {
                            Text(reminderTimesError)
                                .font(.caption)
                                .foregroundStyle(Color(uiColor: .systemRed))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                SparkFormCard(title: "疗程", titleSystemImage: "calendar") {
                    VStack(spacing: 12) {
                        DatePicker("开始日期", selection: $draft.startDate, displayedComponents: .date)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Toggle("设置结束日期", isOn: $draft.hasEndDate)
                            .font(.subheadline.weight(.medium))
                        if draft.hasEndDate {
                            DatePicker("结束日期", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        SparkFormTextRow(title: "疗程天数", text: $draft.durationDays, placeholder: "可选，如 7", keyboardVisible: $sheetKeyboardVisible)
                            .keyboardType(.numberPad)
                    }
                }

                SparkFormCard(title: "状态与提醒", titleSystemImage: "bell.badge.fill") {
                    VStack(spacing: 12) {
                        Toggle("开启提醒", isOn: $draft.reminderEnabled)
                            .font(.subheadline.weight(.medium))
                        Picker("计划状态", selection: $draft.status) {
                            Text("执行中").tag("active")
                            Text("已暂停").tag("paused")
                            Text("已完成").tag("completed")
                            Text("已取消").tag("cancelled")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                SparkFormCard(title: "说明", titleSystemImage: "note.text") {
                    SparkFormTextAreaRow(title: "用药说明", text: $draft.instructions, minHeight: 80, maxHeight: 160, placeholder: "饭前/饭后、禁忌或医嘱备注", keyboardVisible: $sheetKeyboardVisible)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .systemBackground)))
            .padding(16)
            .padding(.bottom, 86)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var selectedMedicineBoxTitle: String {
        selectedMedicineBox.map { $0.drugName.nilIfBlank ?? $0.genericName.nilIfBlank ?? "未命名药品" } ?? "选择药箱药品"
    }

    private var selectedMedicineBoxSubtitle: String {
        guard let selectedMedicineBox else {
            return "可从药箱选择，也可在选择页新增药品"
        }
        let detail = [selectedMedicineBox.strength.nilIfBlank, selectedMedicineBox.dosageForm.nilIfBlank, stockText(selectedMedicineBox)]
            .compactMap { $0 }
            .joined(separator: " · ")
        return detail.isEmpty ? "已关联药箱药品" : detail
    }

    private func handleMedicineBoxSaved(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
            medicineBoxes[index] = box
        } else {
            medicineBoxes.insert(box, at: 0)
        }
        onMedicineBoxSaved(box)
    }

    private func applyMedicineBoxSelection(_ box: SparkMedicalSyncAPI.RemoteMedicineBox?) {
        draft.medicineBoxID = box?.id
        guard let box else { return }
        if draft.drugName.nilIfBlank == nil {
            draft.drugName = box.drugName.nilIfBlank ?? box.genericName
        }
        if draft.doseUnit.nilIfBlank == nil {
            draft.doseUnit = box.unit
        }
    }

    private func submitDraft() {
        switch mode {
        case .localEdit(_, let onSubmit):
            guard validateDraft() else { return }
            onSubmit(draft)
            dismiss()
        case .create, .serverEdit:
            Task { await submitToServer() }
        }
    }

    @MainActor
    private func submitToServer() async {
        guard validateDraft(), isSubmitting == false else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let payload = try draft.payload(memberID: memberID)
            let saved: SparkMedicalSyncAPI.RemoteMedicationPlan
            switch mode {
            case .create:
                saved = try await workflowAPI.create(
                    SparkMedicalSyncAPI.RemoteMedicationPlan.self,
                    kind: .medicationPlans,
                    body: payload
                )
            case .serverEdit(let existing):
                saved = try await workflowAPI.update(
                    SparkMedicalSyncAPI.RemoteMedicationPlan.self,
                    kind: .medicationPlans,
                    id: existing.id,
                    body: payload
                )
            case .localEdit:
                return
            }
            onServerSaved?(saved)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func validateDraft() -> Bool {
        guard canSubmit else {
            alertMessage = draft.validationMessage
            return false
        }
        return true
    }

    private var modeLogLabel: String {
        switch mode {
        case .create:
            return "create"
        case .serverEdit:
            return "serverEdit"
        case .localEdit:
            return "localEdit"
        }
    }
}

private struct MedicationPlanMedicineBoxPickerPage: View {
    let memberID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let onMedicineBoxSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    let onSelect: (SparkMedicalSyncAPI.RemoteMedicineBox?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var selectedMedicineBoxID: Int?
    @State private var sheetDestination: MedicineBoxSheetDestination?

    init(
        memberID: Int,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        selectedMedicineBoxID: Int?,
        workflowAPI: SparkMedicalWorkflowAPI,
        onMedicineBoxSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onSelect: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox?) -> Void
    ) {
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.onMedicineBoxSaved = onMedicineBoxSaved
        self.onSelect = onSelect
        _medicineBoxes = State(initialValue: medicineBoxes)
        _selectedMedicineBoxID = State(initialValue: selectedMedicineBoxID)
    }

    private var sortedBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] {
        medicineBoxes.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var medicineTypeOptions: [String] {
        MedicineBoxTypeCatalog.options(in: medicineBoxes)
    }

    var body: some View {
        List {
            Section {
                Button {
                    selectedMedicineBoxID = nil
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Label("不关联药箱药品", systemImage: "link.badge.minus")
                        Spacer()
                        if selectedMedicineBoxID == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }

            Section("药箱药品") {
                if sortedBoxes.isEmpty {
                    Text("暂无药箱药品")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedBoxes, id: \.id) { box in
                        HStack(spacing: 12) {
                            Button {
                                selectedMedicineBoxID = box.id
                                onSelect(box)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(box.drugName.nilIfBlank ?? box.genericName.nilIfBlank ?? "未命名药品")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text([box.strength.nilIfBlank, box.dosageForm.nilIfBlank, stockText(box)].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if selectedMedicineBoxID == box.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                sheetDestination = .serverEdit(box)
                            } label: {
                                Image(systemName: "pencil.circle")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("编辑药品")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("选择药品")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sheetDestination = .create
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("新增药品")
            }
        }
        .sheet(item: $sheetDestination) { destination in
            MedicineBoxFormView(
                mode: destination.formMode,
                memberID: memberID,
                workflowAPI: workflowAPI,
                typeOptions: medicineTypeOptions,
                onServerSaved: upsertMedicineBox
            )
        }
    }

    private func upsertMedicineBox(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
            medicineBoxes[index] = box
        } else {
            medicineBoxes.insert(box, at: 0)
        }
        onMedicineBoxSaved(box)
        selectedMedicineBoxID = box.id
        onSelect(box)
        sheetDestination = nil
    }
}

struct MedicationPlanDraft {
    var medicalCaseID: Int?
    var medicineBoxID: Int?
    var prescriptionID: Int?
    var drugName = ""
    var dosePerTime = ""
    var doseValue = ""
    var doseUnit = "片"
    var frequencyText = ""
    var frequencyCode = ""
    var reminderTimesText = "08:00"
    var startDate = Date()
    var hasEndDate = false
    var endDate = Date()
    var durationDays = ""
    var instructions = ""
    var reminderEnabled = true
    var status = "active"

    init() {}

    init(existing: SparkMedicalSyncAPI.RemoteMedicationPlan) {
        medicalCaseID = existing.medicalCase
        medicineBoxID = existing.medicineBox
        prescriptionID = existing.prescription
        drugName = existing.drugName
        dosePerTime = existing.dosePerTime
        doseValue = existing.doseValue.map { $0.formatted(.number.precision(.fractionLength(0...3))) } ?? ""
        doseUnit = existing.doseUnit
        frequencyText = existing.frequencyText
        frequencyCode = existing.frequencyCode
        reminderTimesText = existing.reminderTimes.map(\.time).joined(separator: ", ")
        startDate = existing.startDate
        if let endDate = existing.endDate {
            hasEndDate = true
            self.endDate = endDate
        }
        durationDays = existing.durationDays.map(String.init) ?? ""
        instructions = existing.instructions
        reminderEnabled = existing.reminderEnabled
        status = existing.status
    }

    var doseValueValue: Double? {
        doseValue.nilIfBlank.flatMap(Double.init)
    }

    var durationDaysValue: Int? {
        guard let value = durationDays.nilIfBlank else { return 0 }
        return Int(value)
    }

    var reminderTimesError: String? {
        parseReminderTimes().error
    }

    var validationMessage: String {
        if drugName.nilIfBlank == nil {
            return "请填写药品名称"
        }
        if dosePerTime.nilIfBlank == nil {
            return "请填写单次剂量"
        }
        if frequencyText.nilIfBlank == nil {
            return "请填写服药频次"
        }
        if durationDaysValue == nil {
            return "疗程天数必须是整数"
        }
        if let reminderTimesError {
            return reminderTimesError
        }
        if hasEndDate && endDate < startDate {
            return "结束日期不能早于开始日期"
        }
        return "请完善服药计划信息"
    }

    fileprivate func payload(memberID: Int) throws -> MedicationPlanPayload {
        let reminderTimesResult = parseReminderTimes()
        if let error = reminderTimesResult.error {
            throw MedicationPlanFormError.invalidReminderTimes(error)
        }
        return MedicationPlanPayload(
            member: memberID,
            medicalCase: medicalCaseID,
            medicineBox: medicineBoxID,
            prescription: prescriptionID,
            drugName: drugName.trimmed,
            dosePerTime: dosePerTime.trimmed,
            doseValue: doseValueValue,
            doseUnit: doseUnit.nilIfBlank ?? "片",
            frequencyText: frequencyText.trimmed,
            frequencyCode: frequencyCode.nilIfBlank ?? "",
            reminderTimes: reminderTimesResult.times,
            startDate: MedicalDateCoding.encodeDateOnly(startDate),
            endDate: hasEndDate ? MedicalDateCoding.encodeDateOnly(endDate) : nil,
            durationDays: durationDaysValue.flatMap { $0 > 0 ? $0 : nil },
            instructions: instructions.nilIfBlank ?? "",
            reminderEnabled: reminderEnabled,
            status: status,
            extra: [:]
        )
    }

    private func parseReminderTimes() -> (times: [SparkMedicalSyncAPI.MedicationReminderTime], error: String?) {
        let rawItems = reminderTimesText
            .components(separatedBy: CharacterSet(charactersIn: ",，、;； \n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        var result: [SparkMedicalSyncAPI.MedicationReminderTime] = []
        var seen = Set<String>()
        for item in rawItems {
            guard Self.isValidTimeText(item) else {
                return ([], "提醒时间格式应为 HH:mm，例如 08:00")
            }
            guard seen.insert(item).inserted else { continue }
            result.append(.init(time: item, dose: doseValueValue))
        }
        return (result, nil)
    }

    private static func isValidTimeText(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }
}

private struct MedicationPlanPayload: Encodable {
    let member: Int
    let medicalCase: Int?
    let medicineBox: Int?
    let prescription: Int?
    let drugName: String
    let dosePerTime: String
    let doseValue: Double?
    let doseUnit: String
    let frequencyText: String
    let frequencyCode: String
    let reminderTimes: [SparkMedicalSyncAPI.MedicationReminderTime]
    let startDate: String
    let endDate: String?
    let durationDays: Int?
    let instructions: String
    let reminderEnabled: Bool
    let status: String
    let extra: [String: String]

    enum CodingKeys: String, CodingKey {
        case member, prescription, instructions, status, extra
        case medicalCase = "medical_case"
        case medicineBox = "medicine_box"
        case drugName = "drug_name"
        case dosePerTime = "dose_per_time"
        case doseValue = "dose_value"
        case doseUnit = "dose_unit"
        case frequencyText = "frequency_text"
        case frequencyCode = "frequency_code"
        case reminderTimes = "reminder_times"
        case startDate = "start_date"
        case endDate = "end_date"
        case durationDays = "duration_days"
        case reminderEnabled = "reminder_enabled"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(member, forKey: .member)
        try container.encodeNullable(medicalCase, forKey: .medicalCase)
        try container.encodeNullable(medicineBox, forKey: .medicineBox)
        try container.encodeNullable(prescription, forKey: .prescription)
        try container.encode(drugName, forKey: .drugName)
        try container.encode(dosePerTime, forKey: .dosePerTime)
        try container.encodeNullable(doseValue, forKey: .doseValue)
        try container.encode(doseUnit, forKey: .doseUnit)
        try container.encode(frequencyText, forKey: .frequencyText)
        try container.encode(frequencyCode, forKey: .frequencyCode)
        try container.encode(reminderTimes, forKey: .reminderTimes)
        try container.encode(startDate, forKey: .startDate)
        try container.encodeNullable(endDate, forKey: .endDate)
        try container.encodeNullable(durationDays, forKey: .durationDays)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(reminderEnabled, forKey: .reminderEnabled)
        try container.encode(status, forKey: .status)
        try container.encode(extra, forKey: .extra)
    }
}

private enum MedicationPlanFormError: LocalizedError {
    case invalidReminderTimes(String)

    var errorDescription: String? {
        switch self {
        case .invalidReminderTimes(let message):
            return message
        }
    }
}

private struct MedicationPlanCard: View {
    let plan: SparkMedicalSyncAPI.RemoteMedicationPlan
    let medicineBox: SparkMedicalSyncAPI.RemoteMedicineBox?
    let records: [SparkMedicalSyncAPI.RemoteMedicationRecord]

    private var takenCount: Int {
        records.filter { $0.status == "taken" }.count
    }

    private var subtitle: String {
        [
            plan.dosePerTime.nilIfBlank,
            plan.frequencyText.nilIfBlank,
            plan.reminderTimes.map(\.time).joined(separator: ", ").nilIfBlank
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "pills.fill")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                    .frame(width: 40, height: 40)
                    .background(Color(uiColor: .systemBlue).opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.drugName.nilIfBlank ?? "未命名药品")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle.isEmpty ? "暂无补充信息" : subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(planStatusText(plan.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(plan.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(plan.status).opacity(0.12), in: Capsule())
            }

            HStack(spacing: 12) {
                Label("\(takenCount)/\(records.count)", systemImage: "checkmark.circle")
                if let medicineBox {
                    Label(stockText(medicineBox), systemImage: "shippingbox")
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MedicationPlanDetailPage: View {
    let plan: SparkMedicalSyncAPI.RemoteMedicationPlan
    let records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    let memberID: Int?
    let workflowAPI: SparkMedicalWorkflowAPI
    let onSaved: (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void
    let onDeleted: (Int) -> Void
    let onMedicineBoxSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentPlan: SparkMedicalSyncAPI.RemoteMedicationPlan
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var alertMessage: String?

    init(
        plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        memberID: Int?,
        workflowAPI: SparkMedicalWorkflowAPI,
        onSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void,
        onDeleted: @escaping (Int) -> Void,
        onMedicineBoxSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    ) {
        self.plan = plan
        self.records = records
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.onMedicineBoxSaved = onMedicineBoxSaved
        _currentPlan = State(initialValue: plan)
        _medicineBoxes = State(initialValue: medicineBoxes)
    }

    private var sortedRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord] {
        records.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var medicineBox: SparkMedicalSyncAPI.RemoteMedicineBox? {
        currentPlan.medicineBox.flatMap { id in
            medicineBoxes.first(where: { $0.id == id })
        }
    }

    var body: some View {
        List {
            Section("服药计划") {
                DetailRow(title: "药品", value: currentPlan.drugName)
                DetailRow(title: "剂量", value: currentPlan.dosePerTime)
                DetailRow(title: "频次", value: currentPlan.frequencyText)
                DetailRow(title: "提醒", value: currentPlan.reminderTimes.map(\.time).joined(separator: ", "))
                DetailRow(title: "状态", value: planStatusText(currentPlan.status))
                if let medicineBox {
                    DetailRow(title: "药箱剩余", value: stockText(medicineBox))
                }
                if currentPlan.instructions.isEmpty == false {
                    DetailRow(title: "说明", value: currentPlan.instructions)
                }
            }

            Section("服药记录") {
                if sortedRecords.isEmpty {
                    Text("暂无服药记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedRecords, id: \.id) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(record.scheduledAt.formatted(date: .omitted, time: .shortened))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(recordStatusText(record.status))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(record.status == "taken" ? Color(uiColor: .systemGreen) : Color(uiColor: .secondaryLabel))
                            }
                            Text("计划剂量 \(record.plannedDose)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let takenAt = record.takenAt {
                                Text("实际时间 \(takenAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if record.actualDose.isEmpty == false {
                                Text("实际剂量 \(record.actualDose)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(currentPlan.drugName.nilIfBlank ?? "服药计划")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .disabled(memberID == nil)

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let memberID {
                MedicationPlanFormView(
                    mode: .serverEdit(existing: currentPlan),
                    memberID: memberID,
                    medicineBoxes: medicineBoxes,
                    workflowAPI: workflowAPI,
                    onMedicineBoxSaved: handleMedicineBoxSaved,
                    onServerSaved: { saved in
                        currentPlan = saved
                        onSaved(saved)
                        showingEditSheet = false
                    }
                )
            } else {
                Text("请先选择成员")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("确认删除", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await deleteCurrentPlan() }
            }
        } message: {
            Text("删除后该服药计划及关联记录将不再显示。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onChange(of: plan) { newValue in
            currentPlan = newValue
        }
    }

    private func handleMedicineBoxSaved(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
            medicineBoxes[index] = box
        } else {
            medicineBoxes.insert(box, at: 0)
        }
        onMedicineBoxSaved(box)
    }

    @MainActor
    private func deleteCurrentPlan() async {
        guard isDeleting == false else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await workflowAPI.delete(kind: .medicationPlans, id: currentPlan.id)
            onDeleted(currentPlan.id)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.isEmpty ? "未填写" : value)
                .multilineTextAlignment(.trailing)
        }
    }
}

private func stockText(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
    "\(box.remainingQuantity.formatted(.number.precision(.fractionLength(0...2))))/\(box.totalQuantity.formatted(.number.precision(.fractionLength(0...2)))) \(box.unit)"
}

private func planStatusText(_ status: String) -> String {
    switch status {
    case "active":
        return "执行中"
    case "paused":
        return "未开始"
    case "completed":
        return "已完成"
    case "cancelled":
        return "已取消"
    default:
        return status
    }
}

private func recordStatusText(_ status: String) -> String {
    switch status {
    case "scheduled":
        return "待服药"
    case "taken":
        return "已服药"
    case "skipped":
        return "已漏服"
    case "snoozed":
        return "稍后提醒"
    default:
        return status
    }
}

private func statusColor(_ status: String) -> Color {
    switch status {
    case "active":
        return Color(uiColor: .systemBlue)
    case "paused":
        return Color(uiColor: .systemOrange)
    case "completed":
        return Color(uiColor: .systemGreen)
    case "cancelled":
        return Color(uiColor: .systemGray)
    default:
        return Color(uiColor: .secondaryLabel)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

#Preview("Medication Plans") {
    CompatibleNavigationContainer {
        MedicationsListPage(
            completeData: nil,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            memberContextStore: AppContainer.preview.memberContextStore
        )
    }
}
