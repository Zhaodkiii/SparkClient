import SwiftUI

/// 用药执行中心页面（主视图）
/// 展示用户当日/选定日期的用药计划、待执行用药、已完成用药记录，支持日期切换、用药记录提交
struct MedicationExecutionCenterPage: View {
    let medicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    let medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let initialRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    let memberID: Int?
    let medicalQueryAPI: SparkMedicalQueryAPI
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let notificationClient: any NotificationClient
    let logger: Logger
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let memberContextStore: MemberContextStore?
    let medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel?
    let aiSettingsViewModel: AISettingsViewModel?
    /// 个人药箱入口所需的完整 Home 依赖（含成员上下文与上传 ViewModel）
    let homeDependencies: HomeFeatureDependencies?
    let initialFocus: MedicationExecutionInitialFocus?
    let onMedicationPlansChanged: (([SparkMedicalSyncAPI.RemoteMedicationPlan]) -> Void)?
    let onPrescriptionsChanged: (([SparkMedicalSyncAPI.RemotePrescription]) -> Void)?
    let onMedicineBoxesChanged: (([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var recordsByDayID: [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]] = [:]
    @State private var loadedWindow: MedicationExecutionRecordWindow?
    @State private var loadingWindowID: String?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var logSheet: MedicationExecutionLogSheetContext?
    @State private var dateStripScrollID: String?
    @State private var didApplyInitialFocus = false
    private let calendar = Calendar.current
    private let logModule = LogModule.home

    init(
        medicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        initialRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        memberID: Int?,
        medicalQueryAPI: SparkMedicalQueryAPI,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        logger: Logger,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil,
        memberContextStore: MemberContextStore? = nil,
        medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel? = nil,
        aiSettingsViewModel: AISettingsViewModel? = nil,
        homeDependencies: HomeFeatureDependencies? = nil,
        initialFocus: MedicationExecutionInitialFocus? = nil,
        onMedicationPlansChanged: (([SparkMedicalSyncAPI.RemoteMedicationPlan]) -> Void)? = nil,
        onPrescriptionsChanged: (([SparkMedicalSyncAPI.RemotePrescription]) -> Void)? = nil,
        onMedicineBoxesChanged: (([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void)? = nil
    ) {
        self.medicationPlans = medicationPlans
        self.medicineBoxes = medicineBoxes
        self.initialRecords = initialRecords
        self.memberID = memberID
        self.medicalQueryAPI = medicalQueryAPI
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
        self.logger = logger
        self.completeData = completeData
        self.memberContextStore = memberContextStore
        self.medicalDocumentUploadViewModel = medicalDocumentUploadViewModel
        self.aiSettingsViewModel = aiSettingsViewModel
        self.homeDependencies = homeDependencies
        self.initialFocus = initialFocus
        self.onMedicationPlansChanged = onMedicationPlansChanged
        self.onPrescriptionsChanged = onPrescriptionsChanged
        self.onMedicineBoxesChanged = onMedicineBoxesChanged
    }

    private var selectedDayStart: Date {
        calendar.startOfDay(for: selectedDate)
    }

    private var selectedDayRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord] {
        MedicationExecutionRecordCache.records(for: selectedDayStart, in: recordsByDayID, calendar: calendar)
    }

    private var dateStripDays: [MedicationExecutionDateItem] {
        (-45...45).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: Date()) else {
                return nil
            }
            return MedicationExecutionDateItem(date: calendar.startOfDay(for: date), calendar: calendar)
        }
    }

    private var scheduledDoses: [MedicationExecutionDose] {
        MedicationExecutionPlanner.scheduledDoses(
            plans: medicationPlans,
            medicineBoxes: medicineBoxes,
            records: selectedDayRecords,
            on: selectedDayStart,
            calendar: calendar
        )
    }

    private var pendingDoses: [MedicationExecutionDose] {
        scheduledDoses.filter { $0.isCompleted == false }
    }

    private var completedDoses: [MedicationExecutionDose] {
        scheduledDoses.filter(\.isCompleted)
    }

    private var asNeededPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan] {
        medicationPlans
            .filter { MedicationExecutionPlanner.isPlanActive($0, on: selectedDayStart, calendar: calendar) }
//            .filter { $0.reminderTimes.isEmpty }
            .sorted { $0.drugName < $1.drugName }
    }

    private var medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox] {
        Dictionary(uniqueKeysWithValues: medicineBoxes.map { ($0.id, $0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                dateHeader
                    .padding(.horizontal, 20)
                dateStrip
                recordSection
                    .padding(.horizontal, 20)
                if completedDoses.isEmpty == false {
                    completedSection
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("用药")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                AnyView(medicationListToolbarLink)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                AnyView(medicineBoxToolbarLink)
            }
        }
        .overlay {
            if isLoading || isSaving {
                ProgressView()
                    .tint(.accentColor)
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .sheet(item: $logSheet) { context in
            MedicationExecutionLogSheet(
                context: context,
                isSaving: isSaving,
                fileTransferService: fileTransferService,
                onCancel: { logSheet = nil },
                onDone: { selections in
                    Task { await saveSelections(selections, for: context.doses) }
                }
            )
        }
        .task {
            if let initialFocus {
                selectedDate = initialFocus.scheduledAt
            }
            await loadRecordWindow(centeredAt: selectedDayStart, preferInitialRecords: true)
            await applyInitialFocusIfNeeded()
        }
        .onChange(of: selectedDayStart) { newValue in
            Task {
                await loadRecordWindow(centeredAt: newValue, preferInitialRecords: false)
                await applyInitialFocusIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var medicationListToolbarLink: some View {
        if let memberContextStore,
           let medicalDocumentUploadViewModel,
           let aiSettingsViewModel {
            MainNavigationLink {
                MedicationsListPage(
                    completeData: completeData,
                    workflowAPI: workflowAPI,
                    medicalQueryAPI: medicalQueryAPI,
                    fileTransferService: fileTransferService,
                    memberContextStore: memberContextStore,
                    medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
                    aiSettingsViewModel: aiSettingsViewModel,
                    notificationClient: notificationClient,
                    logger: logger,
                    homeDependencies: homeDependencies,
                    onMedicationPlansChanged: onMedicationPlansChanged,
                    onPrescriptionsChanged: onPrescriptionsChanged,
                    onMedicineBoxesChanged: onMedicineBoxesChanged
                )

            } label: {
                Label(
                    L10n.text("home.medical.list.medications.title", fallback: "服药计划"),
                    systemImage: "list.bullet.rectangle"
                )
                .font(.footnote.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private var medicineBoxToolbarLink: some View {
        // 个人药箱入口：复用 FamilyMedicineCabinetPage 的 personal 模式
        if let memberID,
           let homeDependencies {
            MainNavigationLink {
                FamilyMedicineCabinetPage(
                    entryMemberID: memberID,
                    mode: .personal,
                    initialMedicineBoxes: medicineBoxes,
                    dependencies: homeDependencies,
                    onMedicineBoxesChanged: { boxes in
                        onMedicineBoxesChanged?(boxes)
                    }
                )
            } label: {
                Label(
                    L10n.text("home.medical.list.medications.action.medicine_box", fallback: "药箱"),
                    systemImage: "pills.fill"
                )
                .font(.footnote.weight(.semibold))
            }
        }
    }

    private var dateHeader: some View {
        VStack(spacing: 12) {
            Text(MedicationExecutionSupport.longDateTitle(selectedDayStart, calendar: calendar))
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
       

        }
    }

    @ViewBuilder
    private var dateStrip: some View {
        if #available(iOS 17.0, *) {
            ios17DateStrip
        } else {
            legacyDateStripFallback
        }
    }

    @available(iOS 17.0, *)
    private var ios17DateStrip: some View {
        GeometryReader { geometry in
            let horizontalInset = max(
                0,
                (geometry.size.width - MedicationExecutionDateStripMetrics.itemWidth) / 2
            )

            VStack(spacing: 0) {
                VStack(spacing: -5) {
                    Divider()
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(height: 22)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: MedicationExecutionDateStripMetrics.itemSpacing) {
                        ForEach(dateStripDays) { item in
                            Button {
                                selectedDate = item.date
                                dateStripScrollID = item.id
                                MedicationExecutionSupport.impact(style: .light)
                            } label: {
                                MedicationExecutionDateDot(
                                    date: item.date,
                                    isSelected: calendar.isDate(
                                        item.date,
                                        inSameDayAs: selectedDayStart
                                    ),
                                    isLoaded: isDateInLoadedWindow(item.date),
                                    progress: MedicationExecutionPlanner.progress(
                                        plans: medicationPlans,
                                        medicineBoxes: medicineBoxes,
                                        records: MedicationExecutionRecordCache.records(
                                            for: item.date,
                                            in: recordsByDayID,
                                            calendar: calendar
                                        ),
                                        on: item.date,
                                        calendar: calendar
                                    ),
                                    calendar: calendar
                                )
                                .frame(width: MedicationExecutionDateStripMetrics.itemWidth)
                            }
                            .buttonStyle(.plain)
                            .frame(width: MedicationExecutionDateStripMetrics.itemWidth)
                            .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, horizontalInset, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $dateStripScrollID, anchor: .center)
                .task(id: dateStripInitialScrollKey) {
                    await MainActor.run {
                        dateStripScrollID = nil
                    }
                    try? await Task.sleep(for: .milliseconds(80))
                    await MainActor.run {
                        let targetID = MedicationExecutionDateItem.id(
                            for: selectedDayStart,
                            calendar: calendar
                        )
                        guard dateStripDays.contains(where: { $0.id == targetID }) else {
                            return
                        }
                        dateStripScrollID = targetID
                    }
                }
                .onChange(of: dateStripScrollID) { _, newID in
                    guard let newID else { return }
                    guard let item = dateStripDays.first(where: { $0.id == newID }) else { return }
                    guard calendar.isDate(
                        item.date,
                        inSameDayAs: selectedDayStart
                    ) == false else {
                        return
                    }
                    selectedDate = item.date
                    MedicationExecutionSupport.impact(style: .light)
                }
                .onChange(of: selectedDayStart) { _, newDate in
                    let targetID = MedicationExecutionDateItem.id(
                        for: newDate,
                        calendar: calendar
                    )
                    guard dateStripDays.contains(where: { $0.id == targetID }) else {
                        return
                    }
                    guard targetID != dateStripScrollID else {
                        return
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        dateStripScrollID = targetID
                    }
                }
                .frame(height: 86)
            }
        }
        .frame(height: MedicationExecutionDateStripMetrics.stripHeight)
    }

    private var dateStripInitialScrollKey: String {
        let targetID = MedicationExecutionDateItem.id(
            for: selectedDayStart,
            calendar: calendar
        )
        return [
            dateStripDays.first?.id ?? "",
            dateStripDays.last?.id ?? "",
            "\(dateStripDays.count)",
            targetID
        ].joined(separator: "_")
    }

    private var legacyDateStripFallback: some View {
        GeometryReader { geometry in
            let horizontalInset = max(
                0,
                (geometry.size.width - MedicationExecutionDateStripMetrics.itemWidth) / 2
            )

            VStack(spacing: 0) {
                Divider()
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(height: 22)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: MedicationExecutionDateStripMetrics.itemSpacing) {
                        ForEach(dateStripDays) { item in
                            Button {
                                selectedDate = item.date
                                MedicationExecutionSupport.impact(style: .light)
                            } label: {
                                MedicationExecutionDateDot(
                                    date: item.date,
                                    isSelected: calendar.isDate(item.date, inSameDayAs: selectedDayStart),
                                    isLoaded: isDateInLoadedWindow(item.date),
                                    progress: MedicationExecutionPlanner.progress(
                                        plans: medicationPlans,
                                        medicineBoxes: medicineBoxes,
                                        records: MedicationExecutionRecordCache.records(
                                            for: item.date,
                                            in: recordsByDayID,
                                            calendar: calendar
                                        ),
                                        on: item.date,
                                        calendar: calendar
                                    ),
                                    calendar: calendar
                                )
                                .frame(width: MedicationExecutionDateStripMetrics.itemWidth)
                            }
                            .buttonStyle(.plain)
                            .frame(width: MedicationExecutionDateStripMetrics.itemWidth)
                        }
                    }
                    .padding(.horizontal, horizontalInset)
                }
                .frame(height: 86)
            }
        }
        .frame(height: MedicationExecutionDateStripMetrics.stripHeight)
    }

    private func isDateInLoadedWindow(_ day: Date) -> Bool {
        loadedWindow?.contains(day, calendar: calendar) ?? false
    }

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("记录")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            if pendingDoses.isEmpty {
                MedicationExecutionAllDoneCard()
            } else {
                VStack(spacing: 14) {
                    ForEach(MedicationExecutionPlanner.groupByTime(pendingDoses), id: \.timeText) { group in
                        MedicationExecutionPendingCard(
                            timeText: group.timeText,
                            doses: group.doses,
                            fileTransferService: fileTransferService,
                            onAdd: {
                                logSheet = MedicationExecutionLogSheetContext(
                                    title: "记录于 \(group.timeText)",
                                    date: selectedDayStart,
                                    doses: group.doses
                                )
                            }
                        )
                    }
                }
            }

            if asNeededPlans.isEmpty == false {
                MedicationExecutionAsNeededCard {
                    let doses = asNeededPlans.enumerated().map { index, plan in
                        MedicationExecutionPlanner.asNeededDose(
                            plan: plan,
                            medicineBoxesByID: medicineBoxesByID,
                            date: selectedDayStart,
                            sequence: index + 1,
                            calendar: calendar
                        )
                    }
                    logSheet = MedicationExecutionLogSheetContext(title: "全部药品", date: selectedDayStart, doses: doses)
                }
            }
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("已记录")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                let groups = MedicationExecutionPlanner.groupByTime(completedDoses)
                ForEach(groups, id: \.timeText) { group in
                    MedicationExecutionCompletedGroup(group: group)
                    if group.timeText != groups.last?.timeText {
                        Divider()
                            .padding(.leading, 8)
                    }
                }
            }
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
    }

    @MainActor
    private func loadRecordWindow(centeredAt day: Date, preferInitialRecords: Bool) async {
        guard let memberID else { return }

        let shouldShowBlockingLoader = MedicationExecutionRecordCache.needsWindowFetch(
            for: day,
            loadedWindow: loadedWindow,
            calendar: calendar
        ) && MedicationExecutionRecordCache.records(for: day, in: recordsByDayID, calendar: calendar).isEmpty

        if shouldShowBlockingLoader {
            isLoading = true
        }
        defer { isLoading = false }

        guard let request = MedicationExecutionRecordCache.prepareWindowLoad(
            centeredAt: day,
            loadedWindow: loadedWindow,
            loadingWindowID: loadingWindowID,
            recordsByDayID: recordsByDayID,
            initialRecords: initialRecords,
            preferSeedInitialRecords: preferInitialRecords && calendar.isDateInToday(day),
            calendar: calendar
        ) else {
            return
        }

        loadingWindowID = request.requestID
        if request.recordsByDayID != recordsByDayID {
            recordsByDayID = request.recordsByDayID
        }

        do {
            let fetched = try await medicalQueryAPI.listMedicationRecords(
                memberID: memberID,
                scheduledRange: request.window.scheduledQueryRange
            )
            guard loadingWindowID == request.requestID else { return }

            let result = MedicationExecutionRecordCache.finishWindowLoad(
                fetchedRecords: fetched,
                request: request,
                centeredAt: day,
                calendar: calendar
            )
            loadedWindow = result.loadedWindow
            recordsByDayID = result.recordsByDayID
        } catch {
            guard loadingWindowID == request.requestID else { return }
            notificationClient.error(
                error.localizedDescription,
                title: "加载服药记录失败",
                source: "medical.medication_execution.load"
            )
            logger.warning("用药执行中心加载记录失败 error=\(error.localizedDescription)", module: logModule)
        }

        if loadingWindowID == request.requestID {
            loadingWindowID = nil
        }
    }

    @MainActor
    private func saveSelections(
        _ selections: [MedicationExecutionDose.ID: MedicationDoseLogStatus],
        for doses: [MedicationExecutionDose]
    ) async {
        guard isSaving == false else { return }
        let selectedDoses = doses.filter { selections[$0.id] != nil }
        guard selectedDoses.isEmpty == false else {
            logSheet = nil
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            for dose in selectedDoses {
                guard let status = selections[dose.id] else { continue }
                let saved = try await saveDose(dose, status: status)
                upsertRecord(saved)
                await notifyDoseCompleted(dose: dose, saved: saved)
            }
            logSheet = nil
            MedicationExecutionSupport.impact(style: .medium)
        } catch {
            notificationClient.error(error.localizedDescription, title: "记录用药失败", source: "medical.medication_execution.save")
            logger.warning("用药执行中心保存状态失败 error=\(error.localizedDescription)", module: logModule)
        }
    }

    private func saveDose(
        _ dose: MedicationExecutionDose,
        status: MedicationDoseLogStatus
    ) async throws -> SparkMedicalSyncAPI.RemoteMedicationRecord {
        let takenAt = status == .taken ? MedicalDateCoding.encodeISO8601(Date()) : nil
        let actualDose = status == .taken ? dose.plannedDose : ""

        if let record = dose.record {
            let payload = MedicationRecordUpdatePayload(
                takenAt: takenAt,
                status: status.rawValue,
                actualDose: actualDose,
                notes: record.notes,
                extra: record.extra ?? [:]
            )
            return try await workflowAPI.update(
                SparkMedicalSyncAPI.RemoteMedicationRecord.self,
                kind: .medicationRecords,
                id: record.id,
                body: payload
            )
        }

        let payload = MedicationRecordCreatePayload(
            member: dose.plan.member,
            plan: dose.plan.id,
            scheduledAt: MedicalDateCoding.encodeISO8601(dose.scheduledAt),
            takenAt: takenAt,
            status: status.rawValue,
            plannedDose: dose.plannedDose,
            actualDose: actualDose,
            doseSequence: dose.doseSequence,
            timezone: TimeZone.current.identifier,
            notes: "",
            extra: [:]
        )
        return try await workflowAPI.create(
            SparkMedicalSyncAPI.RemoteMedicationRecord.self,
            kind: .medicationRecords,
            body: payload
        )
    }

    private func upsertRecord(_ record: SparkMedicalSyncAPI.RemoteMedicationRecord) {
        MedicationExecutionRecordCache.upsertRecord(record, calendar: calendar, into: &recordsByDayID)
    }

    @MainActor
    private func applyInitialFocusIfNeeded() async {
        guard didApplyInitialFocus == false else { return }
        guard let initialFocus, initialFocus.shouldOpenLogSheet else { return }
        guard loadingWindowID == nil else { return }

        let targetDoses = scheduledDoses.filter { dose in
            initialFocus.items.contains {
                $0.planID == dose.plan.id && $0.doseSequence == dose.doseSequence
            }
        }

        guard targetDoses.isEmpty == false else {
            if initialFocus.items.isEmpty == false {
                notificationClient.warning(
                    L10n.text("medication_reminder.route.invalid"),
                    title: L10n.text("medication_reminder.title"),
                    source: "medication_reminder"
                )
            }
            didApplyInitialFocus = true
            return
        }

        let pending = targetDoses.filter { $0.isCompleted == false }
        if pending.isEmpty {
            notificationClient.info(
                L10n.text("medication_reminder.route.already_completed"),
                title: L10n.text("medication_reminder.title"),
                source: "medication_reminder"
            )
            didApplyInitialFocus = true
            return
        }

        let timeText = MedicationExecutionPlanner.timeText(for: initialFocus.scheduledAt)
        logSheet = MedicationExecutionLogSheetContext(
            title: "记录于 \(timeText)",
            date: selectedDayStart,
            doses: pending
        )
        didApplyInitialFocus = true
    }

    private func notifyDoseCompleted(
        dose: MedicationExecutionDose,
        saved: SparkMedicalSyncAPI.RemoteMedicationRecord
    ) async {
        guard let homeDependencies,
              case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
        let members = homeDependencies.memberContextStore.context.members
        await homeDependencies.medicationReminderSyncCoordinator.handleDoseCompleted(
            accountID: session.accountID,
            memberID: saved.member,
            planID: saved.plan,
            scheduledAt: saved.scheduledAt,
            doseSequence: saved.doseSequence,
            members: members
        )
    }
}

#Preview("Medication Execution Light") {
    CompatibleNavigationContainer {
        MedicationExecutionCenterPage(
            medicationPlans: [],
            medicineBoxes: [],
            initialRecords: [],
            memberID: nil,
            medicalQueryAPI: AppContainer.preview.backend.medicalQuery,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            fileTransferService: AppContainer.preview.fileTransferService,
            notificationClient: AppContainer.preview.notificationClient,
            logger: AppContainer.preview.logger
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Medication Execution Dark") {
    CompatibleNavigationContainer {
        MedicationExecutionCenterPage(
            medicationPlans: [],
            medicineBoxes: [],
            initialRecords: [],
            memberID: nil,
            medicalQueryAPI: AppContainer.preview.backend.medicalQuery,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            fileTransferService: AppContainer.preview.fileTransferService,
            notificationClient: AppContainer.preview.notificationClient,
            logger: AppContainer.preview.logger
        )
    }
    .preferredColorScheme(.dark)
}
