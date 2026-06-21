import SwiftUI

struct MemberMedicalLongTermMedicationStepView: View {
    @Binding var status: MedicalGuideDisclosureStatus

    let memberID: Int
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let workflowAPI: SparkMedicalWorkflowAPI
    let medicalQueryAPI: SparkMedicalQueryAPI
    let fileTransferService: FileTransferService
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let notificationClient: any NotificationClient
    let homeDependencies: HomeFeatureDependencies?

    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] = []
    @State private var prescriptions: [SparkMedicalSyncAPI.RemotePrescription] = []
    @State private var medicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan] = []
    @State private var todayMedicationRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord] = []
    @State private var isLoading = false
    @State private var showingUploadSheet = false
    @State private var sheetDestination: MedicationPlanSheetDestination?

    private var medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox] {
        Dictionary(uniqueKeysWithValues: medicineBoxes.map { ($0.id, $0) })
    }

    private var recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]] {
        Dictionary(grouping: todayMedicationRecords, by: \.plan)
    }

    private var sortedItems: [MedicalMedicationListItem] {
        MedicalMedicationListBuilder.sortedItems(
            medicationPlans: medicationPlans,
            prescriptions: prescriptions
        )
    }

    private var standaloneItems: [MedicalMedicationListItem] {
        sortedItems.filter {
            if case .standalonePlan = $0 { return true }
            return false
        }
    }

    private var prescriptionItems: [MedicalMedicationListItem] {
        sortedItems.filter {
            if case .prescription = $0 { return true }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            medicationScreeningCard

            if status == .none {
                friendlyTipRow
            }

            if status == .have {
                if isLoading && sortedItems.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    medicationArchiveSection
                    addActionButtons
                }
            }
        }
        .task(id: memberID) {
            await loadMedicationArchive()
        }
        .sheet(isPresented: $showingUploadSheet) {
            MedicalAttachmentUploadListSheet(documentType: .medicationPlan, onConfirm: startMedicationPlanRecognition)
        }
        .sheet(item: $sheetDestination) { destination in
            medicationPlanSheetContent(for: destination)
        }
        .fullScreenCover(isPresented: $medicalDocumentUploadViewModel.isUploadPresented) {
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(
                    viewModel: medicalDocumentUploadViewModel,
                    aiSettingsViewModel: aiSettingsViewModel
                )
            }
        }
        .onChange(of: medicalDocumentUploadViewModel.saveSucceededRevision) { _ in
            Task { await refreshAfterMedicalUploadSave() }
        }
        .onChange(of: status) { newValue in
            if newValue == .none {
                sheetDestination = nil
                showingUploadSheet = false
            } else if newValue == .have, sortedItems.isEmpty {
                Task { await loadMedicationArchive() }
            }
        }
    }

    private var medicationScreeningCard: some View {
        MemberSetupSection(title: "用药情况筛查") {
            VStack(alignment: .leading, spacing: 14) {
                Text("目前是否正在长期服用药物，或有近期的处方用药记录？")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    screeningChoice(
                        title: "无长期用药",
                        isSelected: status == .none,
                        action: { status = .none }
                    )
                    screeningChoice(
                        title: "有用药记录",
                        isSelected: status == .have,
                        action: { status = .have }
                    )
                }
            }
        }
    }

    private var friendlyTipRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("贴心提示：如果没有相关用药情况，请直接点击下方保存即可。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var medicationArchiveSection: some View {
        if sortedItems.isEmpty {
            MemberSetupSection(title: "当前用药档案") {
                Text("暂无用药记录，可通过下方按钮拍照识别或手动添加。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            if standaloneItems.isEmpty == false {
                MemberSetupSection(title: "当前用药档案") {
                    VStack(spacing: 10) {
                        ForEach(standaloneItems) { item in
                            if case .standalonePlan(let plan) = item {
                                MainNavigationLink {
                                    planDetailPage(for: plan)
                                } label: {
                                    MedicationPlanCard(
                                        plan: plan,
                                        medicineBox: plan.medicineBox.flatMap { medicineBoxesByID[$0] },
                                        records: recordsByPlanID[plan.id] ?? [],
                                        fileTransferService: fileTransferService
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if prescriptionItems.isEmpty == false {
                MemberSetupSection(title: "医院处方计划组") {
                    VStack(spacing: 10) {
                        ForEach(prescriptionItems) { item in
                            if case .prescription(_, let prescription, let plans) = item {
                                MainNavigationLink {
                                    MedicationPrescriptionDetailPage(
                                        prescription: prescription,
                                        plans: plans,
                                        medicineBoxes: medicineBoxes,
                                        recordsByPlanID: recordsByPlanID,
                                        memberID: memberID,
                                        completeData: completeData,
                                        memberContextStore: memberContextStore,
                                        workflowAPI: workflowAPI,
                                        fileTransferService: fileTransferService,
                                        notificationClient: notificationClient,
                                        homeDependencies: homeDependencies,
                                        onPrescriptionSaved: upsertPrescription,
                                        onPrescriptionDeleted: removePrescription,
                                        onPlanSaved: upsertMedicationPlan,
                                        onPlanDeleted: removeMedicationPlan
                                    )
                                } label: {
                                    MedicationPrescriptionCard(
                                        prescription: prescription,
                                        plans: plans,
                                        medicineBoxesByID: medicineBoxesByID,
                                        recordsByPlanID: recordsByPlanID,
                                        fileTransferService: fileTransferService,
                                        planDestination: planDetailPage
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var addActionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showingUploadSheet = true
            } label: {
                Label("拍照添加计划", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                sheetDestination = .create
            } label: {
                Label("手动添加", systemImage: "pencil.line")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func medicationPlanSheetContent(for destination: MedicationPlanSheetDestination) -> some View {
        MedicationPlanStepperView(
            mode: destination.planMode,
            memberID: memberID,
            medicineBoxes: medicineBoxes,
            workflowAPI: workflowAPI,
            fileTransferService: fileTransferService,
            notificationClient: notificationClient,
            onMedicineBoxSaved: upsertMedicineBox,
            onServerSaved: upsertMedicationPlan,
            homeDependencies: homeDependencies,
            memberContextStore: memberContextStore
        )
    }

    private func planDetailPage(for plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> some View {
        MedicationPlanDetailPage(
            plan: plan,
            medicineBoxes: medicineBoxes,
            records: recordsByPlanID[plan.id] ?? [],
            memberID: memberID,
            completeData: completeData,
            memberContextStore: memberContextStore,
            workflowAPI: workflowAPI,
            fileTransferService: fileTransferService,
            notificationClient: notificationClient,
            homeDependencies: homeDependencies,
            onSaved: upsertMedicationPlan,
            onDeleted: removeMedicationPlan,
            onMedicineBoxSaved: upsertMedicineBox,
            onMedicineBoxDeleted: removeMedicineBox
        )
    }

    private func screeningChoice(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadMedicationArchive() async {
        guard memberID > 0 else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let plansTask = medicalQueryAPI.listMedicationPlans(memberID: memberID)
            async let prescriptionsTask = medicalQueryAPI.listPrescriptions(memberID: memberID)
            async let boxesTask = medicalQueryAPI.listMedicineBoxes(memberID: memberID)
            let (plans, prescriptionRows, boxes) = try await (plansTask, prescriptionsTask, boxesTask)
            medicationPlans = plans
            prescriptions = prescriptionRows
            medicineBoxes = boxes

            let startOfDay = Calendar.current.startOfDay(for: Date())
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            todayMedicationRecords = try await medicalQueryAPI.listMedicationRecords(
                memberID: memberID,
                scheduledRange: MedicationRecordScheduledRange(
                    scheduledFrom: startOfDay,
                    scheduledToExclusive: endOfDay
                )
            )
        } catch {
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "medical.setup.medication.load")
        }
    }

    @MainActor
    private func refreshAfterMedicalUploadSave() async {
        await loadMedicationArchive()
    }

    @MainActor
    private func startMedicationPlanRecognition(files: [MedicalUploadLocalFile]) {
        showingUploadSheet = false
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .medicationPlan)
    }

    @MainActor
    private func upsertMedicationPlan(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) {
        if let index = medicationPlans.firstIndex(where: { $0.id == plan.id }) {
            medicationPlans[index] = plan
        } else {
            medicationPlans.insert(plan, at: 0)
        }
        sheetDestination = nil
        syncMedicationReminderAfterPlanChange()
    }

    @MainActor
    private func removeMedicationPlan(id: Int) {
        medicationPlans.removeAll { $0.id == id }
        syncMedicationReminderAfterPlanChange()
    }

    @MainActor
    private func upsertPrescription(_ prescription: SparkMedicalSyncAPI.RemotePrescription) {
        if let index = prescriptions.firstIndex(where: { $0.id == prescription.id }) {
            prescriptions[index] = prescription
        } else {
            prescriptions.insert(prescription, at: 0)
        }
    }

    @MainActor
    private func removePrescription(id: Int) {
        prescriptions.removeAll { $0.id == id }
    }

    @MainActor
    private func upsertMedicineBox(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
            medicineBoxes[index] = box
        } else {
            medicineBoxes.insert(box, at: 0)
        }
    }

    @MainActor
    private func removeMedicineBox(id: Int) {
        medicineBoxes.removeAll { $0.id == id }
    }

    private func syncMedicationReminderAfterPlanChange() {
        guard let homeDependencies else { return }
        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
        let coordinator = homeDependencies.medicationReminderSyncCoordinator
        coordinator.activate(accountID: session.accountID)
        coordinator.rebuildAfterPlanChanged(
            accountID: session.accountID,
            members: memberContextStore.context.members
        )
    }
}
