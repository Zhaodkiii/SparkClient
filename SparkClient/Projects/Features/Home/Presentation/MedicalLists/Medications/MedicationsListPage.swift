import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    let fileTransferService: FileTransferService
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    let notificationClient: any NotificationClient

    @State private var selectedFilter: MedicationFilterType = .active
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var medicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    @State private var sheetDestination: MedicationPlanSheetDestination?
    @State private var showingUploadSheet = false
    @State private var showingUploadHost = false

    private let logger: Logger = ConsoleLogger()
    private let logModule = LogModule.home

    init(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        memberContextStore: MemberContextStore,
        medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel,
        notificationClient: any NotificationClient
    ) {
        self.completeData = completeData
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.memberContextStore = memberContextStore
        self.medicalDocumentUploadViewModel = medicalDocumentUploadViewModel
        self.notificationClient = notificationClient
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActionBar
        }
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
                        fileTransferService: fileTransferService,
                        viewModel: medicalDocumentUploadViewModel,
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
                    fileTransferService: fileTransferService,
                    notificationClient: notificationClient,
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
        .sheet(isPresented: $showingUploadSheet) {
            MedicineBoxUploadSheet(
                title: L10n.text("medical.upload.medication_plan.sheet.title", fallback: "选择服药计划图片"),
                headerTitle: L10n.text("medical.upload.medication_plan.sheet.header", fallback: "选择上传方式"),
                headerSubtitle: L10n.text("medical.upload.medication_plan.sheet.subtitle", fallback: "可一次选择多张处方、药品说明或服药计划图片，确认后开始识别。"),
                emptyTitle: L10n.text("medical.upload.medication_plan.sheet.empty.title", fallback: "尚未选择文件"),
                emptySubtitle: L10n.text("medical.upload.medication_plan.sheet.empty.subtitle", fallback: "可拍照、从相册选择或上传 PDF/图片"),
                fileNamePrefix: "medication_plan"
            ) { files in
                startMedicationPlanRecognition(files: files)
            }
        }
        .fullScreenCover(isPresented: $showingUploadHost) {
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(viewModel: medicalDocumentUploadViewModel)
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
                            fileTransferService: fileTransferService,
                            notificationClient: notificationClient,
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
                GeometryReader { proxy in
                    HStack(spacing: 12) {
                        Button {
                            sheetDestination = .create
                        } label: {
                            Label(L10n.text("home.medical.list.medications.action.manual_add", fallback: "手动添加"), systemImage: "plus")
                                .font(.headline)
                                .foregroundStyle(Color(uiColor: .systemPurple))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(
                                    Color(uiColor: .systemPurple).opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color(uiColor: .systemPurple).opacity(0.22), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(memberID == nil)
                        .frame(width: max(112, proxy.size.width * 0.34))

                        Button {
                            showingUploadSheet = true
                        } label: {
                            Label(L10n.text("home.medical.list.medications.action.camera_add_plan", fallback: "拍摄添加计划"), systemImage: "camera.fill")
                                .font(.headline)
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(
                                    Color(uiColor: .systemPurple),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(memberID == nil)
                    }
                }
                .frame(height: 52)
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

    @MainActor
    private func startMedicationPlanRecognition(files: [MedicalUploadLocalFile]) {
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .medicationPlan)
        showingUploadHost = true
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

// MARK: - Medication plan dose (stepper + detail sheet)

private struct MedicationPlanDoseValueStepperRow: View {
    @Binding var text: String
    @Binding var keyboardVisible: Bool

    @FocusState private var isValueFocused: Bool

    private static let minDose: Double = 1
    private static let maxDose: Double = 9999
    private static let step: Double = 1

    private var controlFill: Color { Color(uiColor: .systemPurple).opacity(0.12) }
    private var controlStroke: Color { Color(uiColor: .systemPurple).opacity(0.35) }
    private var accentColor: Color { Color(uiColor: .systemPurple) }

    private var numericValue: Double {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.isEmpty == false, let v = Double(t) else { return 0 }
        return v
    }

    private var canDecrement: Bool {
        numericValue > Self.minDose + 1e-9
    }

    private var canIncrement: Bool {
        numericValue < Self.maxDose - 1e-9
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("medication_plan.form.dose_value", fallback: "剂量数值"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                decrementButton
                valueField
                incrementButton
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: text)
        .onChange(of: isValueFocused) { focused in
            keyboardVisible = focused
        }
    }

    private var decrementButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let v = Double(t), t.isEmpty == false else { return }
            let next = max(Self.minDose, v - Self.step)
            text = Self.formatDose(next)
        } label: {
            Image(systemName: "minus")
                .font(.headline.weight(.semibold))
                .imageScale(.medium)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accentColor)
                .frame(width: 32, height: 32)
                .background(controlFill, in: Circle())
                .overlay(Circle().strokeBorder(controlStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(canDecrement == false)
        .opacity(canDecrement ? 1 : 0.45)
        .accessibilityLabel(L10n.text("medication_plan.form.dose_decrement", fallback: "减少剂量"))
    }

    private var incrementButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                text = Self.formatDose(Self.step)
                return
            }
            let v = Double(t) ?? Self.minDose
            let next = min(Self.maxDose, max(Self.minDose, v) + Self.step)
            text = Self.formatDose(next)
        } label: {
            Image(systemName: "plus")
                .font(.headline.weight(.bold))
                .imageScale(.medium)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(accentColor, in: Circle())
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(canIncrement == false)
        .opacity(canIncrement ? 1 : 0.45)
        .accessibilityLabel(L10n.text("medication_plan.form.dose_increment", fallback: "增加剂量"))
    }

    private var valueField: some View {
        TextField(
            L10n.text("medication_plan.form.dose_value_placeholder", fallback: "如 1"),
            text: $text
        )
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .focused($isValueFocused)
        .keyboardType(.decimalPad)
        .font(.title3.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .frame(maxWidth: .infinity)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
        )
    }

    private static func formatDose(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...3)))
    }
}

private struct MedicationPlanDoseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
//    @Binding var doseValue: String
    @Binding var doseUnit: String
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]

    @State private var tempDoseValue = ""
    @State private var tempDoseUnit = ""
    @FocusState private var doseValueFocused: Bool

    private static let selectedChip = Color(red: 79 / 255, green: 70 / 255, blue: 229 / 255)
    private static let sheetHeaderChromeHeight: CGFloat = 72
    private static let sheetFooterChromeHeight: CGFloat = 88

    private var doseUnitLabels: [String] {
        MedicineSpecificationCatalog.doseUnitMenuOptions(boxes: specOptionBoxes)
    }

    private var prefersEnglish: Bool {
        SparkFormCatalogMenuLocale.prefersEnglish
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    }

    private var trimmedTempDoseUnit: String {
        tempDoseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        CompatibleNavigationContainer {
            AdaptiveToolSheetScrollView(
                bottomContentPadding: 12,
                extraChromeHeight: Self.sheetHeaderChromeHeight + Self.sheetFooterChromeHeight
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    sheetFieldBlock(title: L10n.text("medical_record.medicine_box.spec.dose_value")) {
                        HStack(spacing: prefersEnglish ? 6 : 0) {
                            TextField("5", text: doseValueBinding)
                                .textFieldStyle(.plain)
                                .focused($doseValueFocused)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)

                            if trimmedTempDoseUnit.isEmpty == false {
                                Text(MedicineSpecificationCatalog.displayUnit(stored: trimmedTempDoseUnit, prefersEnglish: prefersEnglish))
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.secondary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    unitChipBlock(
                        title: L10n.text("medical_record.medicine_box.spec.dose_unit"),
                        labels: doseUnitLabels,
                        isSelected: { label in
                            MedicineSpecificationCatalog.storedDoseUnit(fromDisplay: label)
                            == MedicineSpecificationCatalog.storedDoseUnit(fromAny: tempDoseUnit)
                        },
                        onSelect: { label in
                            tempDoseUnit = MedicineSpecificationCatalog.storedDoseUnit(fromDisplay: label)
                        }
                    )
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .navigationTitle(L10n.text("medication_plan.form.single_dose_sheet_title", fallback: "单次剂量数值"))
            .navigationBarTitleDisplayMode(.inline)
            .sparkKeyboardDoneToolbar {
                SparkKeyboardDismiss.endEditing()
            }
            .sparkFormBottomBar(
                canSubmit: true,
                cancelTitle: L10n.text("common.cancel"),
                saveTitle: L10n.text("common.done"),
                saveSystemImage: "checkmark.circle.fill",
                onCancel: {
                    dismiss()
                },
                onSave: {
                    doseUnit = tempDoseValue + tempDoseUnit
                    dismiss()
                }
            )
        }
        .ignoresSafeArea()
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            let parts = MedicineSpecification.doseValueAndStoredUnit(fromBackendDoseUnitField: doseUnit)
            tempDoseValue = parts.value
            tempDoseUnit = parts.unit
        }
    }

    private var doseValueBinding: Binding<String> {
        Binding(
            get: { tempDoseValue },
            set: { tempDoseValue = $0 }
        )
    }

    private func sheetFieldBlock(title: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            field()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator).opacity(0.35))
        }
    }

    private func unitChipBlock(
        title: String,
        labels: [String],
        isSelected: @escaping (String) -> Bool,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .padding(.top, 16)

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(labels, id: \.self) { label in
                    let selected = isSelected(label)
                    Button {
                        onSelect(label)
                    } label: {
                        Text(label)
                            .font(.system(size: 14))
                            .foregroundColor(selected ? .white : Color.primary.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)
                            .background(selected ? Self.selectedChip : Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator).opacity(0.35))
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
            return "新增服药计划"
        case .serverEdit, .localEdit:
            return "编辑服药计划"
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
        .alert("保存失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
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
                SparkFormCard(title: "关联药品", titleSystemImage: "pills.fill") {
                    NavigationLink {
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
                

                SparkFormCard(title: "用药规则", titleSystemImage: "calendar.badge.clock") {
                    VStack(spacing: 16) {
                        SparkFormTextRow(title: "药品名称", text: $draft.drugName, placeholder: "如 阿莫西林胶囊", required: true, keyboardVisible: $sheetKeyboardVisible)
                                                
                        
                        HStack(spacing: 12) {
                            MedicationPlanDoseValueStepperRow(text: $draft.doseValue, keyboardVisible: $sheetKeyboardVisible)
                            
                            SparkFormSheetPickerRow(
                                title: L10n.text("medication_plan.form.single_dose_sheet_title", fallback: "单次剂量单位"),
                                displayValue: draft.doseUnit,
                                placeholder: L10n.text("medication_plan.form.single_dose_sheet_placeholder", fallback: "设置单次剂量数值与单位"),
                                onTap: {
                                    showDoseDetailSheet = true
                                }
                            )
                        }
//                            SparkFormTextRow(title: "单次剂量说明", text: $draft.dosePerTime, placeholder: "如 1片 / 5ml", required: true, keyboardVisible: $sheetKeyboardVisible)
                        
                           SparkFormSheetPickerRow(
                               title: "服药频次",
                               displayValue: draft.reminderFrequencyPickerDisplay,
                               placeholder: "请选择提醒频率",
                               required: true,
                               showsValidationError: draft.isReminderFrequencyComplete == false
                                   || draft.resolvedFrequencyText.nilIfBlank == nil
                           ) {
                               showReminderFrequencySheet = true
                           }
                        
                        
                           if #available(iOS 16.0, *) {
                               MedicationReminderTimesSection(draft: $draft, notificationClient: notificationClient)
                           } else {
                               SparkFormCard(title: "提醒时间", titleSystemImage: "calendar") {
                                   SparkFormTextRow(title: "提醒时间", text: $draft.reminderTimesText, placeholder: "如 08:00, 12:00, 20:00", keyboardVisible: $sheetKeyboardVisible)
                                   if let reminderTimesError = draft.reminderTimesError {
                                       Text(reminderTimesError)
                                           .font(.caption)
                                           .foregroundStyle(Color(uiColor: .systemRed))
                                           .frame(maxWidth: .infinity, alignment: .leading)
                                   }
                               }
                           }

                        SparkFormTextAreaRow(title: "用药说明", text: $draft.instructions, minHeight: 80, maxHeight: 160, placeholder: "饭前/饭后、禁忌或医嘱备注", keyboardVisible: $sheetKeyboardVisible)
                    }
                }
                DisclosureGroup(
                    content: {
                        VStack(spacing: 16) {
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
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    },
                    label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                            Text("疗程与提醒⏰")
                                .font(.headline)

                        }
                    }
                )
                .padding(14)

            }
        }
    }

    private var selectedMedicineBoxTitle: String {
        selectedMedicineBox.map { $0.medicineName.nilIfBlank ?? "未命名药品" } ?? "选择药箱药品"
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

private enum MedicationReminderTimePickerRoute: Identifiable {
    case add
    case edit(index: Int)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let index):
            return "edit_\(index)"
        }
    }
}

@available(iOS 16.0, *)
private struct MedicationReminderTimePickerSheet: View {
    @Binding var selectedTime: Date
    let onConfirm: () -> Void
    @State private var tempTime: Date

    init(selectedTime: Binding<Date>, onConfirm: @escaping () -> Void) {
        self._selectedTime = selectedTime
        self.onConfirm = onConfirm
        self._tempTime = State(initialValue: selectedTime.wrappedValue)
    }

    var body: some View {
        AdaptiveSheetContainer.fixed(
            height: 260,
            onCancel: {},
            onConfirm: {
                selectedTime = tempTime
                onConfirm()
            }
        ) {
            DatePicker(
                "",
                selection: $tempTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

@available(iOS 16.0, *)
private struct MedicationReminderTimesSection: View {
    @Binding var draft: MedicationPlanDraft
    let notificationClient: any NotificationClient

    @State private var timePickerRoute: MedicationReminderTimePickerRoute?
    @State private var timePickerSelection = Date()

    private var slots: [String] {
        draft.orderedReminderTimeSlots
    }

    private var countSubtitle: String {
        let n = slots.count
        return "\(n) 次 / 天"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("用药时间")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 12)
                Text(countSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        timePickerSelection = defaultTimeForNewSlot()
                        timePickerRoute = .add
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 40, height: 40)
                            .background(Color(uiColor: .systemBackground), in: Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新增用药时间")

                    ForEach(Array(slots.enumerated()), id: \.offset) { index, time in
                        Menu {
                            Button {
                                timePickerSelection = MedicationPlanDraft.dateForReminderTimeToken(time)
                                timePickerRoute = .edit(index: index)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                removeSlot(at: index)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(time)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(uiColor: .systemBackground), in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                            )
                        }
                        .accessibilityLabel("用药时间 \(time)")
                    }
                }
                .padding(.vertical, 2)
            }

            if let reminderTimesError = draft.reminderTimesError {
                Text(reminderTimesError)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemRed))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 4)
        .sheet(item: $timePickerRoute) { route in
            MedicationReminderTimePickerSheet(selectedTime: $timePickerSelection) {
                applyPickedTime(route: route)
            }
        }
    }

    private func defaultTimeForNewSlot() -> Date {
        if let last = slots.last {
            return MedicationPlanDraft.dateForReminderTimeToken(last)
        }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 8
        c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }

    private func applyPickedTime(route: MedicationReminderTimePickerRoute) {
        let picked = MedicationPlanDraft.reminderTimeString(from: timePickerSelection)
        guard MedicationPlanDraft.isValidTimeText(picked) else { return }

        var next = slots
        switch route {
        case .add:
            if next.contains(picked) {
                notificationClient.warning(
                    "该提醒时间已存在",
                    source: "medication.plan.reminder_times"
                )
                return
            }
            next.append(picked)
        case .edit(let index):
            guard next.indices.contains(index) else { return }
            if let dup = next.firstIndex(of: picked), dup != index {
                notificationClient.warning(
                    "该提醒时间已存在",
                    source: "medication.plan.reminder_times"
                )
                return
            }
            next[index] = picked
        }
        draft.replaceReminderTimeSlots(next)
    }

    private func removeSlot(at index: Int) {
        var next = slots
        guard next.indices.contains(index) else { return }
        next.remove(at: index)
        draft.replaceReminderTimeSlots(next)
    }
}

private struct MedicationPlanMedicineBoxPickerPage: View {
    let memberID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
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
        fileTransferService: FileTransferService,
        onMedicineBoxSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onSelect: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox?) -> Void
    ) {
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
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

    private func medicineBoxStrengthListSubtitle(_ strength: String) -> String? {
        let raw = strength.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isEmpty == false else { return nil }
        let spec = MedicineSpecification.parse(fromAPIStrength: raw)
        if spec.hasStructuredContent {
            return spec.displayString(prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish)
        }
        return raw
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
                                        Text(box.medicineName.nilIfBlank ?? "未命名药品")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text([
                                            medicineBoxStrengthListSubtitle(box.strength),
                                            box.dosageForm.nilIfBlank,
                                            stockText(box)
                                        ].compactMap { $0 }.joined(separator: " · "))
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
                fileTransferService: fileTransferService,
                typeOptions: medicineTypeOptions,
                specOptionBoxes: medicineBoxes,
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
    var reminderFrequencyType: MedicationReminderFrequencyType = .daily
    var everyNDays: Int = 1
    var weeklyWeekdays: Set<Int> = []
    var frequencyText = ""
    var reminderTimesText = "08:00"
    var startDate = Date()
    var hasEndDate = false
    var endDate = Date()
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
        reminderFrequencyType = MedicationReminderFrequencyType(rawValue: existing.frequencyType) ?? .daily
        everyNDays = min(max(existing.everyNDays ?? 1, 1), 365)
        weeklyWeekdays = Set(existing.weeklyWeekdays.filter { (1...7).contains($0) })
        frequencyText = existing.frequencyText
        if frequencyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            frequencyText = MedicationReminderFrequencySummary.displayLine(
                type: reminderFrequencyType,
                everyNDays: everyNDays,
                weekdays: weeklyWeekdays
            )
        }
        reminderTimesText = existing.reminderTimes.map(\.time).joined(separator: ", ")
        startDate = existing.startDate
        if let endDate = existing.endDate {
            hasEndDate = true
            self.endDate = endDate
        }
        instructions = existing.instructions
        reminderEnabled = existing.reminderEnabled
        status = existing.status
    }

    var doseValueValue: Double? {
        doseValue.nilIfBlank.flatMap(Double.init)
    }

    /// Human-readable `dose_per_time` line from structured fields, e.g. `1 / 5 ml` when both are set.
    static func suggestedDosePerTimeLine(doseValue: String, doseUnit: String, prefersEnglish: Bool) -> String {
        let dv = doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let du = doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let duDisp = du.isEmpty ? "" : MedicineSpecificationCatalog.displayUnit(stored: du, prefersEnglish: prefersEnglish)
        switch (dv.isEmpty, duDisp.isEmpty) {
        case (true, true): return ""
        case (false, true): return dv
        case (true, false): return duDisp
        case (false, false): return "\(dv) / \(duDisp)"
        }
    }

    var isReminderFrequencyComplete: Bool {
        MedicationReminderFrequencySummary.isComplete(
            type: reminderFrequencyType,
            everyNDays: everyNDays,
            weekdays: weeklyWeekdays
        )
    }

    var resolvedFrequencyText: String {
        if let manual = frequencyText.nilIfBlank {
            return manual
        }
        return MedicationReminderFrequencySummary.displayLine(
            type: reminderFrequencyType,
            everyNDays: everyNDays,
            weekdays: weeklyWeekdays
        )
    }

    var reminderFrequencyPickerDisplay: String {
        let line = resolvedFrequencyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty == false { return line }
        return MedicationReminderFrequencySummary.displayLine(
            type: reminderFrequencyType,
            everyNDays: everyNDays,
            weekdays: weeklyWeekdays
        )
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
        if isReminderFrequencyComplete == false {
            return "请完整选择服药频次（每几天需选天数，每周需至少选一天）"
        }
        if resolvedFrequencyText.nilIfBlank == nil {
            return "请填写或生成服药频次说明"
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
        let weeklyPayload: [Int] = {
            guard reminderFrequencyType == .weekly else { return [] }
            return weeklyWeekdays.filter { (1...7).contains($0) }.sorted()
        }()
        return MedicationPlanPayload(
            member: memberID,
            medicalCase: medicalCaseID,
            medicineBox: medicineBoxID,
            prescription: prescriptionID,
            drugName: drugName.trimmed,
            dosePerTime: dosePerTime.trimmed,
            doseValue: doseValueValue,
            doseUnit: doseUnit.nilIfBlank ?? "片",
            frequencyType: reminderFrequencyType.rawValue,
            everyNDays: reminderFrequencyType == .everyNDays ? everyNDays : nil,
            weeklyWeekdays: weeklyPayload,
            frequencyText: resolvedFrequencyText.trimmed,
            reminderTimes: reminderTimesResult.times,
            startDate: MedicalDateCoding.encodeDateOnly(startDate),
            endDate: hasEndDate ? MedicalDateCoding.encodeDateOnly(endDate) : nil,
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

    fileprivate static func isValidTimeText(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }
}

extension MedicationPlanDraft {
    /// 从当前文案中提取有效、去重后的 `HH:mm` 列表（用于用药时间 chips；无效片段被跳过，仍可由 `reminderTimesError` 提示整体验证）。
    fileprivate var orderedReminderTimeSlots: [String] {
        let rawItems = reminderTimesText
            .components(separatedBy: CharacterSet(charactersIn: ",，、;； \n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        var result: [String] = []
        var seen = Set<String>()
        for item in rawItems {
            guard Self.isValidTimeText(item) else { continue }
            let norm = Self.normalizedReminderTimeToken(item)
            guard seen.insert(norm).inserted else { continue }
            result.append(norm)
        }
        return result
    }

    fileprivate mutating func replaceReminderTimeSlots(_ slots: [String]) {
        var seen = Set<String>()
        var unique: [String] = []
        for slot in slots {
            let norm = Self.normalizedReminderTimeToken(slot)
            guard Self.isValidTimeText(norm) else { continue }
            if seen.insert(norm).inserted {
                unique.append(norm)
            }
        }
        unique.sort()
        reminderTimesText = unique.isEmpty ? "" : unique.joined(separator: ", ")
    }

    fileprivate static func normalizedReminderTimeToken(_ value: String) -> String {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    fileprivate static func reminderTimeString(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = min(max(c.hour ?? 0, 0), 23)
        let m = min(max(c.minute ?? 0, 0), 59)
        return String(format: "%02d:%02d", h, m)
    }

    fileprivate static func dateForReminderTimeToken(_ token: String) -> Date {
        let parts = token.split(separator: ":")
        let h = min(max(Int(parts[0]) ?? 8, 0), 23)
        let m = parts.count > 1 ? min(max(Int(parts[1]) ?? 0, 0), 59) : 0
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = h
        c.minute = m
        return Calendar.current.date(from: c) ?? Date()
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
    let frequencyType: String
    let everyNDays: Int?
    let weeklyWeekdays: [Int]
    let frequencyText: String
    let reminderTimes: [SparkMedicalSyncAPI.MedicationReminderTime]
    let startDate: String
    let endDate: String?
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
        case frequencyType = "frequency_type"
        case everyNDays = "every_n_days"
        case weeklyWeekdays = "weekly_weekdays"
        case frequencyText = "frequency_text"
        case reminderTimes = "reminder_times"
        case startDate = "start_date"
        case endDate = "end_date"
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
        try container.encode(frequencyType, forKey: .frequencyType)
        try container.encodeNullable(everyNDays, forKey: .everyNDays)
        try container.encode(weeklyWeekdays, forKey: .weeklyWeekdays)
        try container.encode(frequencyText, forKey: .frequencyText)
        try container.encode(reminderTimes, forKey: .reminderTimes)
        try container.encode(startDate, forKey: .startDate)
        try container.encodeNullable(endDate, forKey: .endDate)
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
    let fileTransferService: FileTransferService
    let notificationClient: any NotificationClient
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
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        onSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void,
        onDeleted: @escaping (Int) -> Void,
        onMedicineBoxSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    ) {
        self.plan = plan
        self.records = records
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
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
                    fileTransferService: fileTransferService,
                    notificationClient: notificationClient,
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
    guard let q = box.totalQuantity else { return "总量未填" }
    return "总量 \(q.formatted(.number.precision(.fractionLength(0...2))))"
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
            fileTransferService: AppContainer.preview.fileTransferService,
            memberContextStore: AppContainer.preview.memberContextStore,
            medicalDocumentUploadViewModel: AppContainer.preview.makeMedicalDocumentUploadViewModel(),
            notificationClient: AppContainer.preview.notificationClient
        )
    }
}
