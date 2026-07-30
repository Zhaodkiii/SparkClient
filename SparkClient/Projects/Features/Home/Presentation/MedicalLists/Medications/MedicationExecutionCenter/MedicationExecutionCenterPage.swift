import SwiftUI
import UIKit

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
    @State private var selectedDate: Date
    @State private var recordsByDayID: [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]] = [:]
    @State private var loadedWindow: MedicationExecutionRecordWindow?
    @State private var loadingWindowID: String?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var logSheet: MedicationExecutionLogSheetContext?
    @State private var dateStripScrollID: String?
    @State private var didApplyInitialFocus = false
    @State private var legacyDateStripDefersServerLoad = false
    @State private var legacyDateLoadTask: Task<Void, Never>?
    @State private var activeRecordLoadToken: UUID?
    @State private var createdAsNeededPlansByBoxID: [Int: SparkMedicalSyncAPI.RemoteMedicationPlan] = [:]
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
        _selectedDate = State(initialValue: initialFocus?.scheduledAt ?? Date())
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

    /// 按需用药：展示全部服药计划（不区分状态、是否有定时提醒）
    private var asNeededPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan] {
        medicationPlans.sorted { $0.drugName < $1.drugName }
    }

    private var asNeededDoses: [MedicationExecutionDose] {
        asNeededPlans.enumerated().map { index, plan in
            MedicationExecutionPlanner.asNeededDose(
                plan: plan,
                medicineBoxesByID: medicineBoxesByID,
                date: selectedDayStart,
                sequence: index + 1,
                calendar: calendar
            )
        }
    }

    private var showsAsNeededCard: Bool {
        memberID != nil && homeDependencies != nil
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
        .navigationTitle(L10n.text("home.medical.medication_execution.nav_title"))
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
                memberID: memberID,
                homeDependencies: homeDependencies,
                medicineBoxes: medicineBoxes,
                medicationPlans: medicationPlans,
                onMedicineBoxesChanged: onMedicineBoxesChanged,
                onMedicineBoxAdded: { logSheet = nil },
                onCancel: { logSheet = nil },
                onDone: { submission in
                    Task { await saveSelections(submission, for: submission.doses) }
                }
            )
        }
        .task(id: selectedDayStart) {
            await loadRecordWindow(
                centeredAt: selectedDayStart,
                preferInitialRecords: initialFocus != nil,
                force: false
            )
            await applyInitialFocusIfNeeded()
        }
        .refreshable {
            await loadRecordWindow(
                centeredAt: selectedDayStart,
                preferInitialRecords: false,
                force: true
            )
            await applyInitialFocusIfNeeded()
        }
        .onDisappear {
            legacyDateLoadTask?.cancel()
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
//        if #available(iOS 17.0, *) {
//            ios17DateStrip
//        } else {
//            legacyDateStripFallback
//        }
        legacyDateStripFallback
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
        VStack(spacing: 0) {
            Divider()
            Image(systemName: "arrowtriangle.down.fill")
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(height: 22)
            MedicationExecutionLegacyDateStripScrollView(
                items: dateStripDays,
                selectedDate: $selectedDate,
                defersServerLoad: $legacyDateStripDefersServerLoad,
                calendar: calendar,
                itemWidth: MedicationExecutionDateStripMetrics.itemWidth,
                itemSpacing: MedicationExecutionDateStripMetrics.itemSpacing,
                onCommit: { committedDate in
                    commitLegacyDateStripDate(committedDate)
                },
                content: { item in
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
            )
            .frame(height: 86)
        }
        .frame(height: MedicationExecutionDateStripMetrics.stripHeight)
    }

    private func commitLegacyDateStripDate(_ date: Date) {
        legacyDateStripDefersServerLoad = true
        legacyDateLoadTask?.cancel()
        legacyDateLoadTask = Task { @MainActor in
            await loadRecordWindow(
                centeredAt: calendar.startOfDay(for: date),
                preferInitialRecords: false,
                force: false
            )
            await applyInitialFocusIfNeeded()
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                legacyDateStripDefersServerLoad = false
            }
        }
    }

    private func isDateInLoadedWindow(_ day: Date) -> Bool {
        loadedWindow?.contains(day, calendar: calendar) ?? false
    }

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("home.medical.medication_execution.section.record"))
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
                                    title: MedicationExecutionSupport.logTitle(at: group.timeText),
                                    date: selectedDayStart,
                                    doses: group.doses
                                )
                            }
                        )
                    }
                }
            }

            if showsAsNeededCard {
                MedicationExecutionAsNeededCard {
                    logSheet = MedicationExecutionLogSheetContext(
                        title: MedicationExecutionSupport.allDrugsLogTitle(),
                        date: selectedDayStart,
                        doses: asNeededDoses,
                        source: .medicationPlans
                    )
                }
            }
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("home.medical.medication_execution.section.recorded"))
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                let groups = MedicationExecutionPlanner.groupByTime(completedDoses)
                ForEach(groups, id: \.timeText) { group in
                    MedicationExecutionCompletedGroup(group: group) {
                        logSheet = MedicationExecutionLogSheetContext(
                            title: MedicationExecutionSupport.logTitle(at: group.timeText),
                            date: selectedDayStart,
                            doses: group.doses
                        )
                    }
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
    private func loadRecordWindow(
        centeredAt day: Date,
        preferInitialRecords: Bool,
        force: Bool
    ) async {
        guard let memberID else { return }

        let loadToken = UUID()
        activeRecordLoadToken = loadToken

        defer {
            if activeRecordLoadToken == loadToken {
                activeRecordLoadToken = nil
                isLoading = false
            }
        }

        let shouldShowBlockingLoader = MedicationExecutionRecordCache.needsWindowFetch(
            for: day,
            loadedWindow: loadedWindow,
            calendar: calendar
        ) && MedicationExecutionRecordCache.records(for: day, in: recordsByDayID, calendar: calendar).isEmpty

        if shouldShowBlockingLoader {
            isLoading = true
        }

        guard let request = MedicationExecutionRecordCache.prepareWindowLoad(
            centeredAt: day,
            loadedWindow: loadedWindow,
            loadingWindowID: loadingWindowID,
            recordsByDayID: recordsByDayID,
            initialRecords: initialRecords,
            preferSeedInitialRecords: preferInitialRecords && calendar.isDateInToday(day),
            force: force,
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
            guard Task.isCancelled == false else { return }
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
            guard Task.isCancelled == false else { return }
            guard loadingWindowID == request.requestID else { return }
            notificationClient.error(
                error.localizedDescription,
                title: L10n.text("home.medical.medication_execution.error.load_failed"),
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
        _ submission: MedicationExecutionLogSubmission,
        for doses: [MedicationExecutionDose]
    ) async {
        guard isSaving == false else { return }
        let selectedDoses = doses.filter { submission.selections[$0.id] != nil }
        guard selectedDoses.isEmpty == false else {
            logSheet = nil
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            for dose in selectedDoses {
                guard let status = submission.selections[dose.id] else { continue }
                let merged = mergedDose(dose, edit: submission.edits[dose.id])
                if shouldSkipSave(original: dose, merged: merged, status: status) { continue }
                let saved = try await saveDose(merged, status: status)
                upsertRecord(saved)
                await notifyDoseCompleted(dose: merged, saved: saved)
            }
            logSheet = nil
            MedicationExecutionSupport.impact(style: .medium)
        } catch {
            notificationClient.error(
                error.localizedDescription,
                title: L10n.text("home.medical.medication_execution.error.save_failed"),
                source: "medical.medication_execution.save"
            )
            logger.warning("用药执行中心保存状态失败 error=\(error.localizedDescription)", module: logModule)
        }
    }

    private func mergedDose(
        _ dose: MedicationExecutionDose,
        edit: MedicationExecutionDoseEdit?
    ) -> MedicationExecutionDose {
        guard let edit else { return dose }
        return MedicationExecutionDose(
            id: dose.id,
            plan: dose.plan,
            scheduledAt: edit.scheduledAt,
            plannedDose: edit.plannedDose,
            doseSequence: dose.doseSequence,
            record: dose.record,
            imageAttachment: dose.imageAttachment
        )
    }

    private func shouldSkipSave(
        original: MedicationExecutionDose,
        merged: MedicationExecutionDose,
        status: MedicationDoseLogStatus
    ) -> Bool {
        guard let record = original.record else { return false }
        guard record.status == status.rawValue else { return false }
        guard record.plannedDose == merged.plannedDose else { return false }
        return calendar.isDate(record.scheduledAt, equalTo: merged.scheduledAt, toGranularity: .minute)
    }

    private func saveDose(
        _ dose: MedicationExecutionDose,
        status: MedicationDoseLogStatus
    ) async throws -> SparkMedicalSyncAPI.RemoteMedicationRecord {
        let plan = try await resolvedPlan(for: dose)
        let takenAt = status == .taken ? MedicalDateCoding.encodeISO8601(Date()) : nil
        let actualDose = status == .taken ? dose.plannedDose : ""

        if let record = dose.record {
            let payload = MedicationRecordUpdatePayload(
                scheduledAt: MedicalDateCoding.encodeISO8601(dose.scheduledAt),
                takenAt: takenAt,
                status: status.rawValue,
                plannedDose: dose.plannedDose,
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
            member: plan.member,
            plan: plan.id,
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

    @MainActor
    private func resolvedPlan(
        for dose: MedicationExecutionDose
    ) async throws -> SparkMedicalSyncAPI.RemoteMedicationPlan {
        if dose.plan.id > 0 {
            return dose.plan
        }
        guard let boxID = dose.plan.medicineBox else {
            return dose.plan
        }
        if let cached = createdAsNeededPlansByBoxID[boxID] {
            return cached
        }
        if let linked = medicationPlans.first(where: { $0.medicineBox == boxID }) {
            return linked
        }

        let payload = MedicationPlanPayload(
            member: dose.plan.member,
            medicalCase: nil,
            medicineBox: boxID,
            prescription: nil,
            drugName: dose.plan.drugName,
            dosePerTime: dose.plan.dosePerTime,
            doseValue: dose.plan.doseValue,
            doseUnit: dose.plan.doseUnit,
            frequencyType: dose.plan.frequencyType,
            everyNDays: dose.plan.everyNDays,
            weeklyWeekdays: dose.plan.weeklyWeekdays,
            frequencyText: dose.plan.frequencyText,
            reminderTimes: [],
            startDate: MedicalDateCoding.encodeDateOnly(dose.plan.startDate),
            endDate: dose.plan.endDate.map { MedicalDateCoding.encodeDateOnly($0) },
            instructions: dose.plan.instructions,
            reminderEnabled: false,
            status: MedicationPlanStatus.asNeeded,
            extra: [:]
        )
        let mutation = try await workflowAPI.createMedicationPlan(payload)
        guard let created = mutation.medicationPlan else {
            throw MedicationExecutionPlanResolutionError.missingCreatedPlan
        }
        createdAsNeededPlansByBoxID[boxID] = created
        onMedicationPlansChanged?(medicationPlans + [created])
        return created
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
            title: MedicationExecutionSupport.logTitle(at: timeText),
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

private enum MedicationExecutionPlanResolutionError: LocalizedError {
    case missingCreatedPlan

    var errorDescription: String? {
        switch self {
        case .missingCreatedPlan:
            return L10n.text("home.medical.medication_execution.error.save_failed")
        }
    }
}

private struct MedicationExecutionLegacyDateStripScrollView: UIViewRepresentable {
    let items: [MedicationExecutionDateItem]
    @Binding var selectedDate: Date
    @Binding var defersServerLoad: Bool
    let calendar: Calendar
    let itemWidth: CGFloat
    let itemSpacing: CGFloat
    let onCommit: (Date) -> Void
    let content: (MedicationExecutionDateItem) -> AnyView
    
    init<Content: View>(
        items: [MedicationExecutionDateItem],
        selectedDate: Binding<Date>,
        defersServerLoad: Binding<Bool>,
        calendar: Calendar,
        itemWidth: CGFloat,
        itemSpacing: CGFloat,
        onCommit: @escaping (Date) -> Void,
        @ViewBuilder content: @escaping (MedicationExecutionDateItem) -> Content
    ) {
        self.items = items
        self._selectedDate = selectedDate
        self._defersServerLoad = defersServerLoad
        self.calendar = calendar
        self.itemWidth = itemWidth
        self.itemSpacing = itemSpacing
        self.onCommit = onCommit
        self.content = { AnyView(content($0)) }
    }
    
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.bounces = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.delegate = context.coordinator
        
        let hostingController = UIHostingController(
            rootView: hostedContent(
                displayedDate: context.coordinator.displayedDate,
                onSelect: { item in context.coordinator.select(item) }
            )
        )
        hostingController.view.backgroundColor = .clear
        scrollView.addSubview(hostingController.view)
        context.coordinator.hostingController = hostingController
        
        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        if scrollView.isDragging == false, scrollView.isDecelerating == false {
            context.coordinator.displayedDate = selectedDate
        }
        context.coordinator.hostingController?.rootView = hostedContent(
            displayedDate: context.coordinator.displayedDate,
            onSelect: { item in context.coordinator.select(item) }
        )
        
        let contentWidth = CGFloat(items.count) * itemWidth + CGFloat(max(items.count - 1, 0)) * itemSpacing
        let frame = CGRect(x: 0, y: 0, width: contentWidth, height: 86)
        context.coordinator.hostingController?.view.frame = frame
        scrollView.contentSize = frame.size
        scrollView.contentInset = contentInset(for: scrollView)
        
        guard scrollView.isDragging == false, scrollView.isDecelerating == false else { return }
        let targetOffset = contentOffset(for: selectedIndex, in: scrollView)
        if abs(scrollView.contentOffset.x - targetOffset) > 0.5 {
            context.coordinator.isProgrammaticScroll = true
            scrollView.setContentOffset(CGPoint(x: targetOffset, y: 0), animated: false)
            context.coordinator.isProgrammaticScroll = false
        }
    }
    
    private func hostedContent(
        displayedDate: Date,
        onSelect: @escaping (MedicationExecutionDateItem) -> Void
    ) -> MedicationExecutionLegacyDateStripContent {
        MedicationExecutionLegacyDateStripContent(
            items: items,
            selectedDate: displayedDate,
            calendar: calendar,
            itemWidth: itemWidth,
            itemSpacing: itemSpacing,
            onSelect: onSelect,
            content: content
        )
    }
    
    private var itemPitch: CGFloat {
        itemWidth + itemSpacing
    }
    
    private var selectedIndex: Int {
        guard let index = items.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) }) else {
            return 0
        }
        return index
    }
    
    private func contentInset(for scrollView: UIScrollView) -> UIEdgeInsets {
        let horizontalInset = max((scrollView.bounds.width - itemWidth) / 2, 0)
        return UIEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
    }
    
    private func contentOffset(for index: Int, in scrollView: UIScrollView) -> CGFloat {
        CGFloat(index) * itemPitch - scrollView.contentInset.left
    }
    
    private func index(for scrollView: UIScrollView) -> Int {
        guard items.isEmpty == false else { return 0 }
        let rawIndex = ((scrollView.contentOffset.x + scrollView.contentInset.left) / itemPitch).rounded()
        return min(max(Int(rawIndex), 0), items.count - 1)
    }
    
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: MedicationExecutionLegacyDateStripScrollView
        var hostingController: UIHostingController<MedicationExecutionLegacyDateStripContent>?
        var isProgrammaticScroll = false
        var displayedDate: Date
        private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        
        init(parent: MedicationExecutionLegacyDateStripScrollView) {
            self.parent = parent
            self.displayedDate = parent.selectedDate
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard isProgrammaticScroll == false else { return }
            highlightItem(at: parent.index(for: scrollView))
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            snap(scrollView)
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if decelerate == false {
                snap(scrollView)
            }
        }
        
        func select(_ item: MedicationExecutionDateItem) {
            commit(item)
            feedbackGenerator.impactOccurred()
        }
        
        private func snap(_ scrollView: UIScrollView) {
            let index = parent.index(for: scrollView)
            let xOffset = parent.contentOffset(for: index, in: scrollView)
            scrollView.setContentOffset(CGPoint(x: xOffset, y: 0), animated: false)
            commitItem(at: index)
            feedbackGenerator.impactOccurred()
        }
        
        private func highlightItem(at index: Int) {
            guard parent.items.indices.contains(index) else { return }
            let item = parent.items[index]
            guard parent.calendar.isDate(item.date, inSameDayAs: displayedDate) == false else { return }
            displayedDate = item.date
            refreshRootView()
            parent.defersServerLoad = true
            parent.selectedDate = item.date
        }
        
        private func commitItem(at index: Int) {
            guard parent.items.indices.contains(index) else { return }
            commit(parent.items[index])
        }
        
        private func commit(_ item: MedicationExecutionDateItem) {
            displayedDate = item.date
            refreshRootView()
            parent.defersServerLoad = true
            parent.selectedDate = item.date
            parent.onCommit(item.date)
        }
        
        private func refreshRootView() {
            hostingController?.rootView = parent.hostedContent(
                displayedDate: displayedDate,
                onSelect: { [weak self] item in
                    self?.select(item)
                }
            )
        }
    }
}

private struct MedicationExecutionLegacyDateStripContent: View {
    let items: [MedicationExecutionDateItem]
    let selectedDate: Date
    let calendar: Calendar
    let itemWidth: CGFloat
    let itemSpacing: CGFloat
    let onSelect: (MedicationExecutionDateItem) -> Void
    let content: (MedicationExecutionDateItem) -> AnyView

    var body: some View {
        HStack(spacing: itemSpacing) {
            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    content(item)
                        .frame(width: itemWidth)
                }
                .buttonStyle(.plain)
                .frame(width: itemWidth)
            }
        }
        .frame(height: 86)
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
