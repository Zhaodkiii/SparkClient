import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    let fileTransferService: FileTransferService
    let notificationClient: any NotificationClient
    let onMedicineBoxSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    let onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void)?

    @State private var draft: MedicationPlanDraft
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @State private var sheetKeyboardVisible = false
    @State private var showReminderFrequencySheet = false
    @State private var showDoseDetailSheet = false
    /// Last `dosePerTime` produced from `doseValue`/`doseUnit`; used to avoid overwriting custom user text.
    @State private var lastAutoSuggestedDosePerTime: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    /// 在测量的滚动内容（内嵌导航 + sparkFormBottomBar ）外的 Chrome 浏览器，与 MedicineBoxFormView 的分离数学对齐。
    private static let formSheetNavChromeHeight: CGFloat = 72
    private static let formSheetBottomBarChromeHeight: CGFloat = 88

    init(
        mode: Mode,
        memberID: Int,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        onMedicineBoxSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void)? = nil
    ) {
        self.mode = mode
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
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
        && draft.isReminderFrequencyComplete
        && draft.resolvedFrequencyText.nilIfBlank != nil
        && draft.reminderTimesError == nil
        && (draft.hasEndDate == false || draft.endDate >= draft.startDate)
    }

    private var navigationTitle: String {
        switch mode {
        case .create:
            return L10n.text("medication_plan.form.create_title", fallback: "新增服药计划")
        case .serverEdit, .localEdit:
            return L10n.text("medication_plan.form.edit_title", fallback: "编辑服药计划")
        }
    }

    var body: some View {
        CompatibleNavigationContainer {
            formContent
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
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
        .background(Color(uiColor: .systemBackground))
        .interactiveDismissDisabled(isSubmitting)
        .alert(L10n.text("medication_plan.form.save_failed", fallback: "保存失败"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button(L10n.text("common.got_it"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: $showReminderFrequencySheet) {
            MedicationReminderFrequencySheet(
                type: draft.reminderFrequencyType,
                everyNDays: draft.everyNDays,
                weekdays: draft.weeklyWeekdays,
                summaryText: draft.frequencyText
            ) { type, everyN, weekdays, text in
                draft.reminderFrequencyType = type
                draft.everyNDays = everyN
                draft.weeklyWeekdays = weekdays
                draft.frequencyText = text
            }
        }
        .sheet(isPresented: $showDoseDetailSheet) {
            MedicationPlanDoseDetailSheet(
                doseUnit: $draft.doseUnit,
                specOptionBoxes: medicineBoxes
            )
        }
        .onAppear {
            syncDosePerTimeWithDoseFields()
        }
        .onChange(of: draft.doseValue) { _ in
            syncDosePerTimeWithDoseFields()
        }
        .onChange(of: draft.doseUnit) { _ in
            syncDosePerTimeWithDoseFields()
        }
    }

    private func currentSuggestedDosePerTimeLine() -> String {
        MedicationPlanDraft.suggestedDosePerTimeLine(
            doseValue: draft.doseValue,
            doseUnit: draft.doseUnit,
            prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish
        )
    }

    private func syncDosePerTimeWithDoseFields() {
        let suggested = currentSuggestedDosePerTimeLine()
        let cur = draft.dosePerTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastAutoSuggestedDosePerTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldApply = cur.isEmpty || last.map { cur == $0 } == true
        if shouldApply, draft.dosePerTime != suggested {
            draft.dosePerTime = suggested
        }
        lastAutoSuggestedDosePerTime = suggested
    }

    private var formContent: some View {
        AdaptiveToolSheetScrollView(
            bottomContentPadding: 0,
            extraChromeHeight: Self.formSheetNavChromeHeight + Self.formSheetBottomBarChromeHeight
        ) {
            VStack(spacing: 14) {
                SparkFormCard(title: L10n.text("medication_plan.form.section.linked_medicine", fallback: "关联药品"), titleSystemImage: "pills.fill") {
                    MainNavigationLink {
                        MedicationPlanMedicineBoxPickerPage(
                            memberID: memberID,
                            medicineBoxes: medicineBoxes,
                            selectedMedicineBoxID: draft.medicineBoxID,
                            workflowAPI: workflowAPI,
                            fileTransferService: fileTransferService,
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
                        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                

                SparkFormCard(title: L10n.text("medication_plan.form.section.rules", fallback: "用药规则"), titleSystemImage: "calendar.badge.clock") {
                    VStack(spacing: 16) {
                        SparkFormTextRow(
                            title: L10n.text("medication_plan.form.field.drug_name", fallback: "药品名称"),
                            text: $draft.drugName,
                            placeholder: L10n.text("medication_plan.form.drug_name_placeholder", fallback: "如 阿莫西林胶囊"),
                            required: true,
                            keyboardVisible: $sheetKeyboardVisible
                        )
                                                
                        
                        HStack(spacing: 12) {
                            MedicationPlanDoseValueStepperRow(
                                text: $draft.doseValue,
                                keyboardVisible: $sheetKeyboardVisible,
                                controlStyle: .custom
                            )

                            SparkFormSheetPickerRow(
                                title: L10n.text("medication_plan.form.single_dose_unit_sheet_title", fallback: "单次剂量单位"),
                                displayValue: draft.doseUnit,
                                placeholder: L10n.text("medication_plan.form.single_dose_sheet_placeholder", fallback: "设置单次剂量数值与单位"),
                                onTap: {
                                    showDoseDetailSheet = true
                                }
                            )
                        }
//                            SparkFormTextRow(title: "单次剂量说明", text: $draft.dosePerTime, placeholder: "如 1片 / 5ml", required: true, keyboardVisible: $sheetKeyboardVisible)
                        
                           SparkFormSheetPickerRow(
                               title: L10n.text("medication_plan.form.field.frequency", fallback: "服药频次"),
                               displayValue: draft.reminderFrequencyPickerDisplay,
                               placeholder: L10n.text("medication_plan.form.frequency_placeholder", fallback: "请选择提醒频率"),
                               required: true,
                               showsValidationError: draft.isReminderFrequencyComplete == false
                                   || draft.resolvedFrequencyText.nilIfBlank == nil
                           ) {
                               showReminderFrequencySheet = true
                           }
                        
                        
                           MedicationReminderTimesSection(draft: $draft, notificationClient: notificationClient)

                        SparkFormTextAreaRow(
                            title: L10n.text("medication_plan.form.field.instructions", fallback: "用药说明"),
                            text: $draft.instructions,
                            minHeight: 80,
                            maxHeight: 160,
                            placeholder: L10n.text("medication_plan.form.instructions_placeholder", fallback: "饭前/饭后、禁忌或医嘱备注"),
                            keyboardVisible: $sheetKeyboardVisible
                        )
                    }
                }
                DisclosureGroup(
                    content: {
                        VStack(spacing: 16) {
                            SparkFormCard(title: L10n.text("medication_plan.form.section.course", fallback: "疗程"), titleSystemImage: "calendar") {
                                VStack(spacing: 12) {
                                    DatePicker(L10n.text("medication_plan.form.field.start_date", fallback: "开始日期"), selection: $draft.startDate, displayedComponents: .date)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .frame(height: 44)
                                        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Toggle(L10n.text("medication_plan.form.field.set_end_date", fallback: "设置结束日期"), isOn: $draft.hasEndDate)
                                        .font(.subheadline.weight(.medium))
                                    if draft.hasEndDate {
                                        DatePicker(L10n.text("medication_plan.form.field.end_date", fallback: "结束日期"), selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                                            .font(.subheadline.weight(.medium))
                                            .padding(.horizontal, 12)
                                            .frame(height: 44)
                                            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                            }

                            SparkFormCard(title: L10n.text("medication_plan.form.section.status_reminder", fallback: "状态与提醒"), titleSystemImage: "bell.badge.fill") {
                                VStack(spacing: 12) {
                                    Toggle(L10n.text("medication_plan.form.field.reminder_enabled", fallback: "开启提醒"), isOn: $draft.reminderEnabled)
                                        .font(.subheadline.weight(.medium))
                                    Picker(L10n.text("medication_plan.form.field.status", fallback: "计划状态"), selection: $draft.status) {
                                        Text(planStatusText("active")).tag("active")
                                        Text(L10n.text("home.medical.list.medications.status.paused_explicit", fallback: "已暂停")).tag("paused")
                                        Text(planStatusText("completed")).tag("completed")
                                        Text(planStatusText("cancelled")).tag("cancelled")
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    },
                    label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                            Text(L10n.text("medication_plan.form.section.course_reminder", fallback: "疗程与提醒"))
                                .font(.headline)

                        }
                    }
                )
                .padding(14)

            }
        }
    }

    private var selectedMedicineBoxTitle: String {
        selectedMedicineBox.map { $0.medicineName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed", fallback: "未命名药品") }
        ?? L10n.text("medication_plan.form.select_medicine_box", fallback: "选择药箱药品")
    }

    private var selectedMedicineBoxSubtitle: String {
        guard let selectedMedicineBox else {
            return L10n.text("medication_plan.form.select_medicine_box_subtitle", fallback: "可从药箱选择，也可在选择页新增药品")
        }
        let detail = [selectedMedicineBox.strength.nilIfBlank, selectedMedicineBox.dosageForm.nilIfBlank, stockText(selectedMedicineBox)]
            .compactMap { $0 }
            .joined(separator: " · ")
        return detail.isEmpty ? L10n.text("medication_plan.form.linked_medicine_box", fallback: "已关联药箱药品") : detail
    }

//    private var medicationPlanDoseDetailDisplay: String {
//        let dv = draft.doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
//        let du = draft.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
//        let pref = SparkFormCatalogMenuLocale.prefersEnglish
//        let unitDisplay = du.isEmpty ? "" : MedicineSpecificationCatalog.displayUnit(stored: du, prefersEnglish: pref)
//        if dv.isEmpty, du.isEmpty { return "" }
//        if dv.isEmpty { return unitDisplay }
//        if du.isEmpty { return dv }
//        return pref ? "\(dv) \(unitDisplay)" : "\(dv)\(unitDisplay)"
//    }

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
            draft.drugName = box.medicineName
        }
        let apiDose = box.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiDose.isEmpty {
            draft.doseUnit = apiDose
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
