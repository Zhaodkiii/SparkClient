import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MedicationPlanStepperView: View {
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
    let homeDependencies: HomeFeatureDependencies?
    let memberContextStore: MemberContextStore?
    let reminderPostSaveController: MedicationReminderPostSaveController?

    @State private var draft: MedicationPlanDraft
    @State private var boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var isSpecificationPresented = false
    @State private var isSchedulePresented = false
    @State private var isReviewPresented = false
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @State private var sheetKeyboardVisible = false
    @State private var showMedicineBoxPicker = false
    @State private var showDoseDetailSheet = false
    @State private var showFrequencySheet = false
    @State private var showShareSheet = false
    @State private var pendingShareMember: Member?
    @State private var lastAutoSuggestedDosePerTime: String?

    init(
        mode: Mode,
        memberID: Int,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        onMedicineBoxSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void)? = nil,
        homeDependencies: HomeFeatureDependencies? = nil,
        memberContextStore: MemberContextStore? = nil,
        reminderPostSaveController: MedicationReminderPostSaveController? = nil
    ) {
        self.mode = mode
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
        self.onMedicineBoxSaved = onMedicineBoxSaved
        self.onServerSaved = onServerSaved
        self.homeDependencies = homeDependencies
        self.memberContextStore = memberContextStore
        self.reminderPostSaveController = reminderPostSaveController
        _boxes = State(initialValue: medicineBoxes)

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
        return boxes.first(where: { $0.id == medicineBoxID })
    }

    private var selectedMember: Member? {
        memberContextStore?.context.members.first(where: { $0.id == memberID })
    }

    private var isSelfMember: Bool {
        selectedMember?.relationship == "self"
    }

    private var canGoNextFromName: Bool {
        draft.drugName.nilIfBlank != nil
    }

    private var canGoNextFromSpecification: Bool {
        draft.dosePerTime.nilIfBlank != nil
    }

    private var canGoNextFromSchedule: Bool {
        draft.isReminderFrequencyComplete
        && draft.resolvedFrequencyText.nilIfBlank != nil
        && draft.reminderTimesError == nil
        && (draft.hasEndDate == false || draft.endDate >= draft.startDate)
    }

    private var canSubmit: Bool {
        canGoNextFromName && canGoNextFromSpecification && canGoNextFromSchedule && isSubmitting == false
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
        CompatibleNavigationContainer(legacyStackStyle: true) {
            nameStep
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
        .sheet(isPresented: $showMedicineBoxPicker) {
            if #available(iOS 16.0, *) {
                CompatibleNavigationContainer {
                    MedicationPlanMedicineBoxPickerPage(
                        memberID: memberID,
                        medicineBoxes: boxes,
                        selectedMedicineBoxID: draft.medicineBoxID,
                        workflowAPI: workflowAPI,
                        fileTransferService: fileTransferService,
                        onMedicineBoxSaved: handleMedicineBoxSaved,
                        onSelect: applyMedicineBoxSelection
                    )
                }
            } else {
                MedicationPlanMedicineBoxPickerPage(
                    memberID: memberID,
                    medicineBoxes: boxes,
                    selectedMedicineBoxID: draft.medicineBoxID,
                    workflowAPI: workflowAPI,
                    fileTransferService: fileTransferService,
                    onMedicineBoxSaved: handleMedicineBoxSaved,
                    onSelect: applyMedicineBoxSelection
                )
            }
        }
        .sheet(isPresented: $showDoseDetailSheet) {
            MedicationPlanDoseDetailSheet(
                doseUnit: $draft.doseUnit,
                specOptionBoxes: boxes
            )
        }
        .sheet(isPresented: $showFrequencySheet) {
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
        .sheet(isPresented: $showShareSheet) {
            if let member = pendingShareMember, let homeDependencies {
                ShareSheet(
                    member: member,
                    shareUseCase: homeDependencies.shareMemberUseCase,
                    inviteUseCase: homeDependencies.memberInviteUseCase
                )
            }
        }
        .alert(L10n.text("medication_plan.form.save_failed", fallback: "保存失败"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button(L10n.text("common.got_it"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var nameStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topHero(
                    systemImage: "pills.fill",
                    accentColor: .systemPurple,
                    title: L10n.text("medication_plan.stepper.name.title", fallback: "药品名称"),
                    subtitle: L10n.text("medication_plan.stepper.name.subtitle", fallback: "先确定药品名称，也可以直接关联药箱里的已有药品")
                )

                SparkFormCard(title: L10n.text("medication_plan.stepper.name.card", fallback: "药品信息"), titleSystemImage: "pills.fill") {
                    VStack(spacing: 14) {
                        SparkFormTextRow(
                            title: L10n.text("medication_plan.form.field.drug_name", fallback: "药品名称"),
                            text: $draft.drugName,
                            placeholder: L10n.text("medication_plan.form.drug_name_placeholder", fallback: "如 阿莫西林胶囊"),
                            required: true,
                            keyboardVisible: $sheetKeyboardVisible
                        )

                        SparkFormSheetPickerRow(
                            title: L10n.text("medication_plan.stepper.linked_medicine", fallback: "关联药品"),
                            displayValue: selectedMedicineBoxTitle,
                            placeholder: L10n.text("medication_plan.stepper.select_linked_medicine", fallback: "选择药箱药品"),
                            required: false
                        ) {
                            showMedicineBoxPicker = true
                        }

                        if let selectedMedicineBox {
                            Text(selectedMedicineBoxSubtitle(for: selectedMedicineBox))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
            .background(
                NavigationLink(
                    destination: specificationStep,
                    isActive: $isSpecificationPresented
                ) {
                    EmptyView()
                }
                .hidden()
            )
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("medication_plan.stepper.name.nav_title", fallback: "药品名称"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .sparkFormBottomBar(
            canSubmit: canGoNextFromName,
            cancelTitle: nil,
            saveTitle: L10n.text("common.next"),
            saveSystemImage: "arrow.right",
            keyboardVisible: $sheetKeyboardVisible,
            onCancel: {},
            onSave: {
                guard canGoNextFromName else { return }
                isSpecificationPresented = true
            }
        )
    }

    private var specificationStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topHero(
                    systemImage: "capsule.fill",
                    accentColor: .systemBlue,
                    title: L10n.text("medication_plan.stepper.spec.title", fallback: "添加药品规格"),
                    subtitle: L10n.text("medication_plan.stepper.spec.subtitle", fallback: "这一步可以跳过，后面还可以再补充")
                )

                SparkFormCard(title: L10n.text("medication_plan.stepper.spec.card", fallback: "规格与单位"), titleSystemImage: "square.and.pencil") {
                    VStack(spacing: 14) {
                        MedicationPlanDoseValueStepperRow(
                            text: $draft.doseValue,
                            keyboardVisible: $sheetKeyboardVisible,
                            controlStyle: .custom,
                            title: L10n.text("medication_plan.form.dose_value", fallback: "规格数值")
                        )

                        SparkFormSheetPickerRow(
                            title: L10n.text("medication_plan.form.single_dose_unit_sheet_title", fallback: "规格单位"),
                            displayValue: draft.doseUnit.nilIfBlank ?? L10n.text("medication_plan.stepper.unit_placeholder", fallback: "选择单位"),
                            placeholder: L10n.text("medication_plan.stepper.unit_placeholder", fallback: "选择单位"),
                            required: false
                        ) {
                            showDoseDetailSheet = true
                        }

                        Text(
                            MedicationPlanDraft.suggestedDosePerTimeLine(
                                doseValue: draft.doseValue,
                                doseUnit: draft.doseUnit,
                                prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
            .background(
                NavigationLink(
                    destination: scheduleStep,
                    isActive: $isSchedulePresented
                ) {
                    EmptyView()
                }
                .hidden()
            )
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("medication_plan.stepper.spec.nav_title", fallback: "添加规格"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .sparkFormBottomBar(
            canSubmit: true,
            cancelTitle: L10n.text("common.back", fallback: "返回"),
            saveTitle: L10n.text("common.next"),
            saveSystemImage: "arrow.right",
            keyboardVisible: $sheetKeyboardVisible,
            onCancel: {
                isSpecificationPresented = false
            },
            onSave: {
                isSchedulePresented = true
            }
        )
    }

    private var scheduleStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topHero(
                    systemImage: "calendar.badge.clock",
                    accentColor: .systemGreen,
                    title: L10n.text("medication_plan.stepper.schedule.title", fallback: "用药时间"),
                    subtitle: L10n.text("medication_plan.stepper.schedule.subtitle", fallback: "设置频次、时间和疗程")
                )

                SparkFormCard(title: L10n.text("medication_plan.form.section.rules", fallback: "用药规则"), titleSystemImage: "calendar.badge.clock") {
                    VStack(spacing: 14) {
                        SparkFormSheetPickerRow(
                            title: L10n.text("medication_plan.form.field.frequency", fallback: "服药频次"),
                            displayValue: draft.reminderFrequencyPickerDisplay,
                            placeholder: L10n.text("medication_plan.form.frequency_placeholder", fallback: "请选择提醒频率"),
                            required: true,
                            showsValidationError: draft.isReminderFrequencyComplete == false || draft.resolvedFrequencyText.nilIfBlank == nil
                        ) {
                            showFrequencySheet = true
                        }

                        if #available(iOS 16.0, *) {
                            MedicationReminderTimesSection(draft: $draft, notificationClient: notificationClient)
                        } else {
                            SparkFormTextRow(
                                title: L10n.text("medication_plan.form.field.reminder_times", fallback: "提醒时间"),
                                text: $draft.reminderTimesText,
                                placeholder: L10n.text("medication_plan.form.reminder_times_placeholder", fallback: "如 08:00, 12:00, 20:00"),
                                required: true,
                                keyboardVisible: $sheetKeyboardVisible
                            )
                            if let reminderTimesError = draft.reminderTimesError {
                                Text(reminderTimesError)
                                    .font(.caption)
                                    .foregroundStyle(Color(uiColor: .systemRed))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        SparkFormTextAreaRow(
                            title: L10n.text("medical_record.forms.field.instructions", fallback: "用药说明"),
                            text: $draft.instructions,
                            minHeight: 80,
                            maxHeight: 160,
                            placeholder: L10n.text("medication_plan.form.instructions_placeholder", fallback: "饭前/饭后、禁忌或医嘱备注"),
                            keyboardVisible: $sheetKeyboardVisible
                        )
                    }
                }

                SparkFormCard(title: L10n.text("medication_plan.stepper.course.card", fallback: "疗程"), titleSystemImage: "calendar") {
                    VStack(spacing: 12) {
                        DatePicker(
                            L10n.text("medication_plan.form.field.start_date", fallback: "开始日期"),
                            selection: $draft.startDate,
                            displayedComponents: .date
                        )
                        .font(.subheadline.weight(.medium))

                        Toggle(L10n.text("medication_plan.form.field.set_end_date", fallback: "设置结束日期"), isOn: $draft.hasEndDate)
                            .font(.subheadline.weight(.medium))

                        if draft.hasEndDate {
                            DatePicker(
                                L10n.text("medication_plan.form.field.end_date", fallback: "结束日期"),
                                selection: $draft.endDate,
                                in: draft.startDate...,
                                displayedComponents: .date
                            )
                            .font(.subheadline.weight(.medium))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
            .background(
                NavigationLink(
                    destination: reviewStep,
                    isActive: $isReviewPresented
                ) {
                    EmptyView()
                }
                .hidden()
            )
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("medication_plan.stepper.schedule.nav_title", fallback: "用药时间"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .sparkFormBottomBar(
            canSubmit: canGoNextFromSchedule,
            cancelTitle: L10n.text("common.back", fallback: "返回"),
            saveTitle: L10n.text("common.next"),
            saveSystemImage: "arrow.right",
            keyboardVisible: $sheetKeyboardVisible,
            onCancel: {
                isSchedulePresented = false
            },
            onSave: {
                guard canGoNextFromSchedule else { return }
                isReviewPresented = true
            }
        )
    }

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topHero(
                    systemImage: "checkmark.seal.fill",
                    accentColor: .systemOrange,
                    title: L10n.text("medication_plan.stepper.review.title", fallback: "检查详细信息"),
                    subtitle: L10n.text("medication_plan.stepper.review.subtitle", fallback: "最后确认一下，再完成保存")
                )

                SparkFormCard(title: L10n.text("medication_plan.stepper.review.card", fallback: "信息摘要"), titleSystemImage: "doc.text.magnifyingglass") {
                    VStack(alignment: .leading, spacing: 12) {
                        summaryRow(title: L10n.text("medication_plan.form.field.drug_name", fallback: "药品名称"), value: draft.drugName.nilIfBlank ?? L10n.text("common.unknown", fallback: "未知"))
                        summaryRow(title: L10n.text("medication_plan.form.field.frequency", fallback: "服药频次"), value: draft.reminderFrequencyPickerDisplay)
                        summaryRow(title: L10n.text("medication_plan.form.field.reminder_times", fallback: "提醒时间"), value: draft.orderedReminderTimeSlots.joined(separator: "、"))
                        summaryRow(
                            title: L10n.text("medication_plan.form.single_dose_unit_sheet_title", fallback: "规格"),
                            value: MedicationPlanDraft.suggestedDosePerTimeLine(
                                doseValue: draft.doseValue,
                                doseUnit: draft.doseUnit,
                                prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish
                            )
                        )
                        summaryRow(
                            title: L10n.text("medication_plan.form.field.start_date", fallback: "开始日期"),
                            value: draft.startDate.formatted(date: .abbreviated, time: .omitted)
                        )
                        if draft.hasEndDate {
                            summaryRow(
                                title: L10n.text("medication_plan.form.field.end_date", fallback: "结束日期"),
                                value: draft.endDate.formatted(date: .abbreviated, time: .omitted)
                            )
                        }
                    }
                }

                SparkFormCard(title: L10n.text("medication_plan.stepper.review.reminder", fallback: "用药提醒"), titleSystemImage: "bell.badge.fill") {
                    Toggle(L10n.text("medication_plan.form.field.reminder_enabled", fallback: "开启提醒"), isOn: $draft.reminderEnabled)
                        .font(.subheadline.weight(.medium))
                }

                if shouldShowCollaborationSection {
                    SparkFormCard(title: L10n.text("medication_plan.stepper.review.collaboration", fallback: "非本人提醒协同"), titleSystemImage: "person.2.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                openShareSheet()
                            } label: {
                                Label(L10n.text("medication_plan.stepper.review.share_member", fallback: "邀请他人通知用药"), systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(homeDependencies == nil || selectedMember == nil)

                            Button {
                                enableLocalReminderForThisDevice()
                            } label: {
                                Label(L10n.text("medication_plan.stepper.review.enable_local", fallback: "在本机开启通知"), systemImage: "bell.badge")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(homeDependencies == nil)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("medication_plan.stepper.review.nav_title", fallback: "检查详细信息"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .sparkFormBottomBar(
            canSubmit: canSubmit,
            cancelTitle: L10n.text("common.back", fallback: "返回"),
            saveTitle: L10n.text("common.done"),
            saveSystemImage: "checkmark.circle.fill",
            keyboardVisible: $sheetKeyboardVisible,
            onCancel: {
                isReviewPresented = false
            },
            onSave: {
                submitDraft()
            }
        )
    }

    private func topHero(systemImage: String, accentColor: UIColor, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 0)
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color(accentColor))
                    .frame(width: 120, height: 120)
                    .background(Color(accentColor).opacity(0.12), in: Circle())
                Spacer(minLength: 0)
            }

            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 110, alignment: .leading)
            Text(value.nilIfBlank ?? L10n.text("common.unknown", fallback: "未知"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shouldShowCollaborationSection: Bool {
        guard let member = selectedMember else { return false }
        return member.relationship != "self"
    }

    private func openShareSheet() {
        guard let member = selectedMember, homeDependencies != nil else { return }
        pendingShareMember = member
        showShareSheet = true
    }

    private func enableLocalReminderForThisDevice() {
        draft.reminderEnabled = true
        guard let homeDependencies else { return }
        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
        Task {
            await homeDependencies.medicationReminderSyncCoordinator.requestSystemPermissionAndRebuild(
                accountID: session.accountID,
                members: memberContextStore?.context.members ?? []
            )
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
        let current = draft.dosePerTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = lastAutoSuggestedDosePerTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldApply = current.isEmpty || previous.map { current == $0 } == true
        if shouldApply, draft.dosePerTime != suggested {
            draft.dosePerTime = suggested
        }
        lastAutoSuggestedDosePerTime = suggested
    }

    private var selectedMedicineBoxTitle: String {
        selectedMedicineBox?.medicineName.nilIfBlank
        ?? L10n.text("medication_plan.stepper.select_linked_medicine", fallback: "选择药箱药品")
    }

    private func selectedMedicineBoxSubtitle(for box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
        let pieces = [
            box.strength.nilIfBlank,
            box.dosageForm.nilIfBlank,
            stockText(box)
        ].compactMap { $0 }
        return pieces.joined(separator: " · ")
    }

    private func handleMedicineBoxSaved(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = boxes.firstIndex(where: { $0.id == box.id }) {
            boxes[index] = box
        } else {
            boxes.insert(box, at: 0)
        }
        onMedicineBoxSaved(box)
    }

    private func applyMedicineBoxSelection(_ box: SparkMedicalSyncAPI.RemoteMedicineBox?) {
        draft.medicineBoxID = box?.id
        guard let box else { return }
        if draft.drugName.nilIfBlank == nil {
            draft.drugName = box.medicineName
        }
        if box.doseUnit.nilIfBlank != nil {
            draft.doseUnit = box.doseUnit
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
            if let reminderPostSaveController, let homeDependencies, let memberContextStore {
                reminderPostSaveController.handlePlanChanged(
                    saved,
                    homeDependencies: homeDependencies,
                    memberContextStore: memberContextStore,
                    memberID: memberID,
                    notificationClient: notificationClient
                )
            }
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
}
