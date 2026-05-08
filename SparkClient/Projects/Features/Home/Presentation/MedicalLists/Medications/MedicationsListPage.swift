import SwiftUI

/// 用药列表项：统一处方批次与单独用药，便于排序与筛选。
private enum MedicationListItem: Identifiable {
    case prescriptionBatch(SparkMedicalSyncAPI.RemotePrescriptionBatchComplete)
    case standaloneMedication(SparkMedicalSyncAPI.RemoteMedication)

    var id: String {
        switch self {
        case .prescriptionBatch(let batch):
            return "batch_\(batch.id)"
        case .standaloneMedication(let medication):
            return "med_\(medication.id)"
        }
    }

    /// 排序时间：优先使用业务时间，没有则回退更新时间。
    var sortDate: Date {
        switch self {
        case .prescriptionBatch(let batch):
            return batch.prescribedAt ?? batch.updatedAt ?? batch.createdAt ?? .distantPast
        case .standaloneMedication(let medication):
            return medication.updatedAt
        }
    }
}

/// 用药筛选：参考 HealthClient 顶部标签页，但基于当前接口字段仅做轻量 UI 分类。
private enum MedicationFilterType: String, Identifiable, CaseIterable {
    case active
    case notStarted
    case completed

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .active:
            return "home.medical.list.medications.filter.active"
        case .notStarted:
            return "home.medical.list.medications.filter.not_started"
        case .completed:
            return "home.medical.list.medications.filter.completed"
        }
    }
}

/// 用药展示状态：当前接口没有完整状态字段，这里只做 UI 分组，不推断医疗语义。
private enum MedicationDisplayStatus {
    case active
    case notStarted
    case completed
}

/// 用药列表页：顶部筛选 + 列表内容 + 底部操作栏。
struct MedicationsListPage: View {
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let fileTransferService: FileTransferService
    let workflowAPI: SparkMedicalWorkflowAPI
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    let onPrescriptionBatchesUpdated: (([SparkMedicalSyncAPI.RemotePrescriptionBatchComplete]) -> Void)?
    let onMedicalCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)?

    @State private var selectedFilter: MedicationFilterType = .active
    @State private var prescriptionBatches: [SparkMedicalSyncAPI.RemotePrescriptionBatchComplete]
    @State private var standaloneMedications: [SparkMedicalSyncAPI.RemoteMedication]

    private let logger: Logger = ConsoleLogger()
    private let logModule = LogModule.home

    init(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        fileTransferService: FileTransferService,
        workflowAPI: SparkMedicalWorkflowAPI,
        memberContextStore: MemberContextStore,
        notificationClient: any NotificationClient,
        onPrescriptionBatchesUpdated: (([SparkMedicalSyncAPI.RemotePrescriptionBatchComplete]) -> Void)? = nil,
        onMedicalCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)? = nil
    ) {
        self.completeData = completeData
        self.fileTransferService = fileTransferService
        self.workflowAPI = workflowAPI
        self.memberContextStore = memberContextStore
        self.notificationClient = notificationClient
        self.onPrescriptionBatchesUpdated = onPrescriptionBatchesUpdated
        self.onMedicalCasesUpdated = onMedicalCasesUpdated
        _prescriptionBatches = State(initialValue: completeData?.prescriptionBatches ?? [])
        _standaloneMedications = State(initialValue: completeData?.standaloneMedications ?? [])
    }

    /// 统一列表数据源：处方批次优先展示，批次内已包含的药品不再重复显示。
    private var sortedItems: [MedicationListItem] {
        var items: [MedicationListItem] = prescriptionBatches.map { .prescriptionBatch($0) }
        let medicationIDsInBatch = Set(prescriptionBatches.flatMap { $0.medications ?? [] }.map(\.id))
        items.append(
            contentsOf: standaloneMedications
                .filter { medicationIDsInBatch.contains($0.id) == false }
                .map { .standaloneMedication($0) }
        )

        return items.sorted { $0.sortDate > $1.sortDate }
    }

    private var filteredItems: [MedicationListItem] {
        sortedItems.filter { item in
            switch selectedFilter {
            case .active:
                return matches(.active, for: item)
            case .notStarted:
                return matches(.notStarted, for: item)
            case .completed:
                return matches(.completed, for: item)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterTabBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if filteredItems.isEmpty {
                emptyStateView
            } else {
                medicationListContent
            }
        }
        .overlay(bottomActionBar, alignment: .bottom)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.medical.list.medications.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            logger.info(
                "打开用药列表 filter=\(selectedFilter.rawValue) total=\(sortedItems.count) filtered=\(filteredItems.count)",
                module: logModule
            )
        }
        .onChange(of: selectedFilter) { newValue in
            logger.info(
                "切换用药筛选 filter=\(newValue.rawValue) filtered=\(filteredItems.count)",
                module: logModule
            )
        }
        .onChange(of: completeData?.prescriptionBatches ?? []) { newValue in
            prescriptionBatches = newValue
        }
        .onChange(of: completeData?.standaloneMedications ?? []) { newValue in
            standaloneMedications = newValue
        }
    }

    // MARK: - 顶部筛选

    private var filterTabBar: some View {
        HStack(spacing: 0) {
            ForEach(MedicationFilterType.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    VStack(spacing: 8) {
                        Text(L10n.text(filter.titleKey))
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

    // MARK: - 列表内容

    private var medicationListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredItems) { item in
                    switch item {
                    case .prescriptionBatch(let batch):
                        MedicationPrescriptionBatchCard(
                            item: batch,
                            fileTransferService: fileTransferService,
                            workflowAPI: workflowAPI,
                            completeData: completeData,
                            memberContextStore: memberContextStore,
                            notificationClient: notificationClient,
                            onMedicalCaseLinked: upsertPrescriptionBatch,
                            onMedicalCaseUpdated: handleMedicalCaseUpdated,
                            onMedicalCaseDeleted: handleMedicalCaseDeleted
                        )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    case .standaloneMedication(let medication):
                        MedicationCard(
                            item: medication,
                            medicalCaseID: prescriptionBatches.first(where: { $0.id == medication.batch })?.medicalCase,
                            workflowAPI: workflowAPI,
                            completeData: completeData,
                            fileTransferService: fileTransferService,
                            memberContextStore: memberContextStore,
                            notificationClient: notificationClient,
                            onBatchMedicalCaseLinked: upsertPrescriptionBatch,
                            onMedicalCaseUpdated: handleMedicalCaseUpdated,
                            onMedicalCaseDeleted: handleMedicalCaseDeleted
                        )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }

                Text(L10n.text("home.medical.list.medications.footer.no_more"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.bottom, 96)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "pills")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(L10n.text("home.medical.list.medications.empty.title"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(L10n.text("home.medical.list.medications.empty.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - 底部操作栏

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color(uiColor: .separator).opacity(0.2))

            VStack(spacing: 12) {
                Button(action: {}) {
                    Text(L10n.text("home.medical.list.medications.action.add_plan"))
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private func upsertPrescriptionBatch(_ batch: SparkMedicalSyncAPI.RemotePrescriptionBatchComplete) {
        if let index = prescriptionBatches.firstIndex(where: { $0.id == batch.id }) {
            prescriptionBatches[index] = batch
        } else {
            prescriptionBatches.insert(batch, at: 0)
        }
        onPrescriptionBatchesUpdated?(prescriptionBatches)
    }

    private func handleMedicalCaseUpdated(_ updated: SparkMedicalSyncAPI.RemoteMedicalCaseSummary) {
        var cases = completeData?.medicalCases ?? []
        if let index = cases.firstIndex(where: { $0.id == updated.id }) {
            cases[index] = updated
        } else {
            cases.insert(updated, at: 0)
        }
        onMedicalCasesUpdated?(cases)
    }

    private func handleMedicalCaseDeleted(_ deletedID: Int) {
        let cases = (completeData?.medicalCases ?? []).filter { $0.id != deletedID }
        onMedicalCasesUpdated?(cases)
    }

    // MARK: - 过滤辅助

    private func matches(_ status: MedicationDisplayStatus, for item: MedicationListItem) -> Bool {
        switch item {
        case .prescriptionBatch(let batch):
            return (batch.medications ?? []).contains { displayStatus(for: $0) == status }
        case .standaloneMedication(let medication):
            return displayStatus(for: medication) == status
        }
    }

    /// 基于当前远端摘要字段生成纯展示状态：
    /// - `durationDays == 0` 视为已结束；
    /// - 无提醒且无提醒时间时视为未开始；
    /// - 其余默认展示为进行中。
    private func displayStatus(for medication: SparkMedicalSyncAPI.RemoteMedication) -> MedicationDisplayStatus {
        if medication.durationDays == 0 {
            return .completed
        }
        if medication.reminderEnabled == false && medication.reminderTimes.isEmpty {
            return .notStarted
        }
        return .active
    }
}

#Preview("Medication List Light") {
    CompatibleNavigationContainer {
        MedicationsListPage(
            completeData: nil,
            fileTransferService: AppContainer.preview.fileTransferService,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            memberContextStore: AppContainer.preview.memberContextStore,
            notificationClient: AppContainer.preview.notificationClient
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Medication List Dark") {
    CompatibleNavigationContainer {
        MedicationsListPage(
            completeData: nil,
            fileTransferService: AppContainer.preview.fileTransferService,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            memberContextStore: AppContainer.preview.memberContextStore,
            notificationClient: AppContainer.preview.notificationClient
        )
    }
    .preferredColorScheme(.dark)
}
