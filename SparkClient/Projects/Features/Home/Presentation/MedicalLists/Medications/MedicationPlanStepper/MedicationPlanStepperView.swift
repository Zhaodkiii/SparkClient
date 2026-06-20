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

    @State private var draft: MedicationPlanDraft
    @State private var boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var path: [MedicationPlanStepperRoute] = []
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @State private var sheetKeyboardVisible = false
    @State private var showMedicineBoxPicker = false
    @State private var showDoseDetailSheet = false
    @State private var showFrequencySheet = false
    @State private var showShareSheet = false
    @State private var pendingShareMember: Member?
    @State private var localReminderEnabled = false
    @State private var originalLocalReminderEnabled = false
    @State private var didLoadLocalReminderAuthorization = false
    @State private var lastAutoSuggestedDosePerTime: String?
    @State private var isLoadingLocalReminderAuthorization = false
    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

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
        memberContextStore: MemberContextStore? = nil
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
        _boxes = State(initialValue: medicineBoxes)

        switch mode {
        case .create:
            var draft = MedicationPlanDraft()
            draft.doseUnit = ""
            _draft = State(initialValue: draft)
        case .serverEdit(let existing):
            _draft = State(initialValue: MedicationPlanDraft(existing: existing))
        case .localEdit(let existing, _):
            _draft = State(initialValue: existing)
        }

        _localReminderEnabled = State(initialValue: false)
        _originalLocalReminderEnabled = State(initialValue: false)
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

    private var shouldShowCollaborationSection: Bool {
        switch mode {
        case .localEdit:
            return false
        case .create, .serverEdit:
            guard let selectedMember else { return false }
            return selectedMember.relationship != "self"
        }
    }

    private var canGoNextFromName: Bool {
        draft.drugName.nilIfBlank != nil
    }

    private var canGoNextFromSpecification: Bool {
        draft.doseValue.nilIfBlank != nil && draft.doseUnit.nilIfBlank != nil
    }

    private var canGoNextFromSchedule: Bool {
        draft.isReminderFrequencyComplete
        && draft.resolvedFrequencyText.nilIfBlank != nil
        && draft.reminderTimesError == nil
        && (draft.hasEndDate == false || draft.endDate >= draft.startDate)
    }

    private var canSubmit: Bool {
        canGoNextFromName && canGoNextFromSchedule && isSubmitting == false
    }

    private var allowsInteractiveDismiss: Bool {
        path.isEmpty
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
        CompatibleRouteNavigationContainer(path: $path, legacyStackStyle: true) {
            nameStep
        } destination: { route in
            switch route {
            case .specification:
                specificationStep
            case .schedule:
                scheduleStep
            case .review:
                reviewStep
            }
        }
        .interactiveDismissDisabled(allowsInteractiveDismiss == false)
        .onAppear {
            syncDosePerTimeWithDoseFields()
        }
        .onChange(of: draft.doseValue) { _ in
            syncDosePerTimeWithDoseFields()
        }
        .onChange(of: draft.doseUnit) { _ in
            syncDosePerTimeWithDoseFields()
        }
        .onAppear {
            loadLocalReminderAuthorizationIfNeeded()
        }
        .sheet(isPresented: $showMedicineBoxPicker) {
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

                MedicationPlanStepperCard(title: L10n.text("medication_plan.stepper.name.card", fallback: "药品信息"),subtitle: L10n.text("medication_plan.stepper.name.subtitle", fallback: "先确定药品名称，也可以直接关联药箱里的已有药品"), systemImage: "pills.fill") {
                    VStack(spacing: 14) {
                        MedicationPlanStepperTextField(
                            title: L10n.text("medication_plan.form.field.drug_name", fallback: "药品名称"),
                            text: $draft.drugName,
                            placeholder: L10n.text("medication_plan.form.drug_name_placeholder", fallback: "如 阿莫西林胶囊"),
                            required: true,
                            keyboardVisible: $sheetKeyboardVisible
                        )

                        MedicationPlanStepperPickerRow(
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
        .medicationPlanStepperBottomBar(
            canSubmit: canGoNextFromName,
            primaryTitle: L10n.text("common.next"),
            primarySystemImage: nil,
            keyboardVisible: $sheetKeyboardVisible,
            onPrimary: {
                guard canGoNextFromName else { return }
                path.append(.specification)
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

                MedicationPlanStepperCard(title: L10n.text("medication_plan.stepper.spec.card", fallback: "规格与单位"), subtitle: L10n.text("medication_plan.stepper.spec.subtitle", fallback: "这一步可以跳过，后面还可以再补充"), systemImage: "square.and.pencil") {
                    VStack(spacing: 14) {
                        MedicationPlanDoseValueStepperRow(
                            text: $draft.doseValue,
                            keyboardVisible: $sheetKeyboardVisible,
                            controlStyle: .systemStepper,
                            title: L10n.text("medication_plan.form.dose_value", fallback: "规格数值")
                        )

                        MedicationPlanStepperPickerRow(
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
        .medicationPlanStepperBottomBar(
            canSubmit: canGoNextFromSpecification,
            backTitle: L10n.text("common.skip", fallback: "跳过"),
            primaryTitle: L10n.text("common.next"),
            primarySystemImage: nil,
            keyboardVisible: $sheetKeyboardVisible,
            onBack: {
                skipSpecificationStep()
            },
            onPrimary: {
                guard canGoNextFromSpecification else { return }
                path.append(.schedule)
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

                MedicationPlanStepperCard(title: L10n.text("medication_plan.form.section.rules", fallback: "用药规则"), subtitle: L10n.text("medication_plan.stepper.schedule.subtitle", fallback: "设置频次、时间和疗程"), systemImage: "calendar.badge.clock") {
                    VStack(spacing: 14) {
                        MedicationPlanStepperPickerRow(
                            title: L10n.text("medication_plan.form.field.frequency", fallback: "服药频次"),
                            displayValue: draft.reminderFrequencyPickerDisplay,
                            placeholder: L10n.text("medication_plan.form.frequency_placeholder", fallback: "请选择提醒频率"),
                            required: true,
                            showsValidationError: draft.isReminderFrequencyComplete == false || draft.resolvedFrequencyText.nilIfBlank == nil
                        ) {
                            showFrequencySheet = true
                        }

                        MedicationReminderTimesSection(draft: $draft, notificationClient: notificationClient)
                    }
                    

                }
                MedicationPlanStepperCard(title: L10n.text("medication_plan.stepper.course.card", fallback: "疗程"), systemImage: "calendar"){
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
                    

                    MedicationPlanStepperTextArea(
                        title: L10n.text("medical_record.forms.field.instructions", fallback: "用药说明"),
                        text: $draft.instructions,
                        placeholder: L10n.text("medication_plan.form.instructions_placeholder", fallback: "饭前/饭后、禁忌或医嘱备注"),
                        keyboardVisible: $sheetKeyboardVisible,
                        minHeight: 120
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
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
        .medicationPlanStepperBottomBar(
            canSubmit: canGoNextFromSchedule,
            backTitle: L10n.text("common.skip", fallback: "跳过"),
            primaryTitle: L10n.text("common.next"),
            primarySystemImage: nil,
            keyboardVisible: $sheetKeyboardVisible,
            onBack: {
                path.append(.review)
            },
            onPrimary: {
                guard canGoNextFromSchedule else { return }
                path.append(.review)
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

                MedicationPlanStepperCard(title: L10n.text("medication_plan.stepper.review.card", fallback: "信息摘要"),subtitle: L10n.text("medication_plan.stepper.review.subtitle", fallback: "最后确认一下，再完成保存"), systemImage: "doc.text.magnifyingglass") {
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

                MedicationPlanStepperCard(title: L10n.text("medication_plan.stepper.review.reminder", fallback: "用药提醒"), systemImage: "bell.badge.fill") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(L10n.text("medication_plan.form.field.reminder_enabled", fallback: "开启提醒"), isOn: $draft.reminderEnabled)
                            .font(.subheadline.weight(.medium))
                        
                        if shouldShowCollaborationSection  && draft.reminderEnabled {
                            VStack(alignment: .leading, spacing: 16) {
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    Button {
                                        openShareSheet()
                                    } label: {
                                        Label(L10n.text("medication_plan.stepper.review.share_member", fallback: "邀请他人通知用药"), systemImage: "square.and.arrow.up")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(homeDependencies == nil || selectedMember == nil)
                                    
                                    Toggle(L10n.text("medication_plan.stepper.review.local_reminder", fallback: "本机提醒开关"), isOn: $localReminderEnabled)
                                        .font(.subheadline.weight(.medium))
                                        .disabled(homeDependencies == nil || isLoadingLocalReminderAuthorization)
                                    
                                    if isLoadingLocalReminderAuthorization {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                }
                            }
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
        .medicationPlanStepperBottomBar(
            canSubmit: canSubmit,
            primaryTitle: L10n.text("common.done"),
            primarySystemImage: nil,
            keyboardVisible: $sheetKeyboardVisible,
            onPrimary: {
                submitDraft()
            }
        )
    }

    private func topHero(systemImage: String, accentColor: UIColor, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 0)
                Image(systemName: systemImage)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color(accentColor))
                    .frame(width: 120, height: 120)
                    .background(Color(accentColor).opacity(0.12), in: Circle())
                Spacer(minLength: 0)
            }
//
//            Text(title)
//                .font(.title2.weight(.bold))
//                .foregroundStyle(.primary)
//
//            Text(subtitle)
//                .font(.subheadline)
//                .foregroundStyle(.secondary)
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

    private func openShareSheet() {
        guard let member = selectedMember, homeDependencies != nil else { return }
        pendingShareMember = member
        showShareSheet = true
    }

    private func loadLocalReminderAuthorizationIfNeeded() {
        guard case .serverEdit(let existing) = mode else { return }
        guard shouldShowCollaborationSection else { return }
        guard didLoadLocalReminderAuthorization == false else { return }
        guard let homeDependencies else { return }
        didLoadLocalReminderAuthorization = true
        isLoadingLocalReminderAuthorization = true
        let planID = existing.id
        Task { @MainActor in
            defer { isLoadingLocalReminderAuthorization = false }
            do {
                let authorization = try await homeDependencies.medicalQueryAPI.fetchMedicationReminderLocalAuthorization(planID: planID)
                localReminderEnabled = authorization.enabled
                originalLocalReminderEnabled = authorization.enabled
                formLog.info(
                    "MedicationPlanStepperView: loaded local reminder authorization planID=\(planID) enabled=\(authorization.enabled) mode=\(modeLogLabel)",
                    module: formLogModule
                )
            } catch {
                localReminderEnabled = false
                originalLocalReminderEnabled = false
                formLog.warning(
                    "MedicationPlanStepperView: failed to load local reminder authorization planID=\(planID) error=\(error.localizedDescription) mode=\(modeLogLabel)",
                    module: formLogModule
                )
            }
        }
    }

    private func syncLocalReminderAuthorizationAfterSaveIfNeeded(savedPlan: SparkMedicalSyncAPI.RemoteMedicationPlan) {
        guard shouldShowCollaborationSection else { return }
        guard let homeDependencies else { return }
        guard localReminderEnabled != originalLocalReminderEnabled else { return }
        let enabled = localReminderEnabled
        let planID = savedPlan.id
        formLog.info(
            "MedicationPlanStepperView: schedule local reminder authorization sync planID=\(planID) enabled=\(enabled) mode=\(modeLogLabel)",
            module: formLogModule
        )
        Task {
            do {
                if enabled {
                    _ = try await homeDependencies.medicalQueryAPI.upsertMedicationReminderLocalAuthorization(
                        planID: planID,
                        enabled: true,
                        source: "medication_plan_stepper_review"
                    )
                } else {
                    try await homeDependencies.medicalQueryAPI.disableMedicationReminderLocalAuthorization(planID: planID)
                }
                formLog.info(
                    "MedicationPlanStepperView: local reminder authorization sync succeeded planID=\(planID) enabled=\(enabled) mode=\(modeLogLabel)",
                    module: formLogModule
                )
            } catch {
                formLog.warning(
                    "MedicationPlanStepperView: local reminder authorization sync failed planID=\(planID) enabled=\(enabled) error=\(error.localizedDescription) mode=\(modeLogLabel)",
                    module: formLogModule
                )
            }
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

    private func skipSpecificationStep() {
        draft.doseValue = ""
        draft.doseUnit = ""
        draft.dosePerTime = ""
        lastAutoSuggestedDosePerTime = ""
        path.append(.schedule)
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
            syncLocalReminderAuthorizationAfterSaveIfNeeded(savedPlan: saved)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func validateDraft() -> Bool {
        guard canSubmit else {
            alertMessage = stepperValidationMessage
            return false
        }
        return true
    }

    private var stepperValidationMessage: String {
        if draft.drugName.nilIfBlank == nil {
            return L10n.text("medication_plan.form.validation.drug_name_required", fallback: "请填写药品名称")
        }
        if draft.isReminderFrequencyComplete == false {
            return L10n.text("medication_plan.form.validation.frequency_incomplete", fallback: "请完整选择服药频次（每几天需选天数，每周需至少选一天）")
        }
        if draft.resolvedFrequencyText.nilIfBlank == nil {
            return L10n.text("medication_plan.form.validation.frequency_text_required", fallback: "请填写或生成服药频次说明")
        }
        if let reminderTimesError = draft.reminderTimesError {
            return reminderTimesError
        }
        if draft.hasEndDate && draft.endDate < draft.startDate {
            return L10n.text("medication_plan.form.validation.end_date_before_start", fallback: "结束日期不能早于开始日期")
        }
        return L10n.text("medication_plan.form.validation.incomplete", fallback: "请完善服药计划信息")
    }
}

private enum MedicationPlanStepperRoute: Hashable {
    case specification
    case schedule
    case review
}
