import Combine
import SwiftUI

struct NutritionEnergyBurnDetailView: View {
    @StateObject private var viewModel: NutritionEnergyBurnViewModel
    @State private var showEditor = false
    @State private var editingRecord: SparkNutritionAPI.RemoteEnergyBurnRecord?

    private let dependencies: NutritionFeatureDependencies
    private let memberID: Int
    private let date: Date

    init(dependencies: NutritionFeatureDependencies, memberID: Int, date: Date) {
        self.dependencies = dependencies
        self.memberID = memberID
        self.date = date
        _viewModel = StateObject(
            wrappedValue: NutritionEnergyBurnViewModel(
                dependencies: dependencies,
                memberID: memberID,
                date: date
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch viewModel.loadState {
                case .idle, .loading:
                    NutritionLoadingStateView(messageKey: "nutrition.energy.loading")
                case .error(let messageKey):
                    NutritionErrorStateView(
                        messageKey: messageKey,
                        retryTitleKey: "nutrition.common.retry"
                    ) {
                        Task { await viewModel.reload() }
                    }
                case .content:
                    if let data = viewModel.viewData {
                        summarySection(data)
                        recordsSection(data)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("nutrition.energy.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if viewModel.canSyncAppleHealth {
                    Button(L10n.text("nutrition.energy.sync_apple_health")) {
                        Task { await viewModel.syncAppleHealth() }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editingRecord = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.reload() }
        .sheet(isPresented: $showEditor) {
            NutritionEnergyBurnEditorView(
                dependencies: dependencies,
                memberID: memberID,
                date: date,
                existingRecord: editingRecord
            ) {
                Task { await viewModel.reload() }
            }
        }
        .alert(
            L10n.text("nutrition.energy.delete.title"),
            isPresented: $viewModel.showDeleteConfirmation
        ) {
            Button(L10n.text("nutrition.common.cancel"), role: .cancel) {}
            Button(L10n.text("nutrition.common.delete"), role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
        } message: {
            if viewModel.pendingDeleteHasAppleHealthID {
                Text(L10n.text("nutrition.apple_health.delete_hint"))
            }
        }
        .alert(
            L10n.text("nutrition.confirm.save_failed.title"),
            isPresented: errorAlertBinding
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            if let key = viewModel.errorMessageKey {
                Text(L10n.text(key))
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessageKey != nil },
            set: { if $0 == false { viewModel.clearError() } }
        )
    }

    private func summarySection(_ data: NutritionEnergyBurnViewData) -> some View {
        NutritionCardContainer {
            VStack(spacing: 12) {
                summaryRow(titleKey: "nutrition.energy.total", value: data.totalEnergyKcal)
                summaryRow(titleKey: "nutrition.energy.apple_health", value: data.appleHealthEnergyKcal)
                summaryRow(titleKey: "nutrition.energy.manual", value: data.manualEnergyKcal)
            }
        }
    }

    private func summaryRow(titleKey: String, value: Double) -> some View {
        HStack {
            Text(L10n.text(titleKey))
                .font(.subheadline)
            Spacer()
            Text(NutritionFormatting.energyKcal(value))
                .font(.subheadline.weight(.semibold))
        }
    }

    private func recordsSection(_ data: NutritionEnergyBurnViewData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("nutrition.energy.records.title"))
                .font(.headline)

            if data.records.isEmpty {
                NutritionEmptyStateView(
                    titleKey: "nutrition.energy.empty.title",
                    subtitleKey: "nutrition.energy.empty.subtitle"
                )
            } else {
                NutritionCardContainer(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(data.records.enumerated()), id: \.element.id) { index, row in
                            burnRow(row)
                            if index < data.records.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    private func burnRow(_ row: NutritionEnergyBurnRowViewData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.activityType.isEmpty ? L10n.text("nutrition.energy.activity.unknown") : row.activityType)
                    .font(.subheadline.weight(.semibold))
                Text(row.burnedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if row.note.isEmpty == false {
                    Text(row.note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(
                    row.isManual
                        ? L10n.text("nutrition.energy.source.manual")
                        : L10n.text("nutrition.energy.source.apple_health")
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(NutritionFormatting.energyKcal(row.energyKcal))
                    .font(.subheadline.weight(.semibold))
                if row.isManual {
                    Menu {
                        Button(L10n.text("nutrition.common.edit")) {
                            editingRecord = viewModel.remoteRecord(for: row.id)
                            showEditor = true
                        }
                        Button(L10n.text("nutrition.common.delete"), role: .destructive) {
                            viewModel.prepareDelete(recordID: row.id, hasAppleHealthID: row.hasAppleHealthID)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
    }
}

struct NutritionEnergyBurnEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NutritionEnergyBurnEditorViewModel

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        date: Date,
        existingRecord: SparkNutritionAPI.RemoteEnergyBurnRecord?,
        onSaved: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: NutritionEnergyBurnEditorViewModel(
                dependencies: dependencies,
                memberID: memberID,
                date: date,
                existingRecord: existingRecord,
                onSaved: onSaved
            )
        )
    }

    var body: some View {
        CompatibleNavigationContainer {
            Form {
                Section {
                    TextField(L10n.text("nutrition.energy.field.energy"), text: $viewModel.state.energyKcal)
                        .keyboardType(.decimalPad)
                    TextField(L10n.text("nutrition.energy.field.activity"), text: $viewModel.state.activityType)
                    DatePicker(
                        L10n.text("nutrition.energy.field.time"),
                        selection: $viewModel.state.burnedAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    TextField(L10n.text("nutrition.energy.field.duration"), text: $viewModel.state.durationMinutes)
                        .keyboardType(.numberPad)
                    TextField(L10n.text("nutrition.energy.field.note"), text: $viewModel.state.note)
                }
            }
            .navigationTitle(
                viewModel.isEditing
                    ? L10n.text("nutrition.energy.edit.title")
                    : L10n.text("nutrition.energy.add.title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("nutrition.common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("nutrition.common.save")) {
                        Task {
                            if await viewModel.save() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .alert(
                L10n.text("nutrition.confirm.save_failed.title"),
                isPresented: errorAlertBinding
            ) {
                Button(L10n.text("common.ok"), role: .cancel) {}
            } message: {
                if let key = viewModel.errorMessageKey {
                    Text(L10n.text(key))
                }
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessageKey != nil },
            set: { if $0 == false { viewModel.clearError() } }
        )
    }
}

@MainActor
final class NutritionEnergyBurnViewModel: ObservableObject {
    @Published private(set) var viewData: NutritionEnergyBurnViewData?
    @Published private(set) var loadState: NutritionHomeLoadState = .idle
    @Published var showDeleteConfirmation = false
    @Published private(set) var errorMessageKey: String?

    private(set) var pendingDeleteRecordID: Int?
    private(set) var pendingDeleteHasAppleHealthID = false

    private let energyBurnUseCase: NutritionEnergyBurnUseCase
    private let healthKitSyncUseCase: NutritionHealthKitSyncUseCase
    private let memberContextStore: MemberContextStore
    private let memberID: Int
    private let date: Date
    private var remoteRecords: [SparkNutritionAPI.RemoteEnergyBurnRecord] = []

    init(dependencies: NutritionFeatureDependencies, memberID: Int, date: Date) {
        self.energyBurnUseCase = dependencies.energyBurnUseCase
        self.healthKitSyncUseCase = dependencies.healthKitSyncUseCase
        self.memberContextStore = dependencies.memberContextStore
        self.memberID = memberID
        self.date = date
    }

    var canSyncAppleHealth: Bool {
        memberContextStore.context.members.first(where: { $0.id == memberID })?.isPrimary == true
    }

    func loadIfNeeded() async {
        guard viewData == nil else { return }
        await reload()
    }

    func reload() async {
        loadState = .loading
        do {
            remoteRecords = try await energyBurnUseCase.listRecords(memberID: memberID, date: date)
            viewData = NutritionViewDataMapper.energyBurnViewData(from: remoteRecords)
            loadState = .content(
                NutritionDashboardViewData(
                    memberID: memberID,
                    date: date,
                    consumedEnergyKcal: 0,
                    remainingEnergyKcal: 0,
                    burnedEnergyKcal: viewData?.totalEnergyKcal ?? 0,
                    targetEnergyKcal: 0,
                    intakeProgress: 0,
                    overview: .init(energyKcal: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0),
                    carbohydrate: .init(current: 0, target: 0, unit: "g"),
                    protein: .init(current: 0, target: 0, unit: "g"),
                    fat: .init(current: 0, target: 0, unit: "g"),
                    macroRatioChart: .init(
                        carbohydrate: .init(currentPercent: 0, targetPercent: 100),
                        protein: .init(currentPercent: 0, targetPercent: 100),
                        fat: .init(currentPercent: 0, targetPercent: 100)
                    ),
                    meals: []
                )
            )
        } catch {
            loadState = .error(messageKey: NutritionErrorMapper.messageKey(for: error))
        }
    }

    func syncAppleHealth() async {
        guard let member = memberContextStore.context.members.first(where: { $0.id == memberID }) else { return }
        await healthKitSyncUseCase.syncTodayIfNeeded(member: member, date: date)
        await reload()
        NotificationCenter.default.post(name: .nutritionEnergyBurnDidChange, object: nil)
    }

    func remoteRecord(for id: Int) -> SparkNutritionAPI.RemoteEnergyBurnRecord? {
        remoteRecords.first(where: { $0.id == id })
    }

    func prepareDelete(recordID: Int, hasAppleHealthID: Bool) {
        pendingDeleteRecordID = recordID
        pendingDeleteHasAppleHealthID = hasAppleHealthID
        showDeleteConfirmation = true
    }

    func confirmDelete() async {
        guard let recordID = pendingDeleteRecordID else { return }
        do {
            try await energyBurnUseCase.deleteRecord(recordID: recordID)
            NotificationCenter.default.post(name: .nutritionEnergyBurnDidChange, object: nil)
            await reload()
        } catch {
            errorMessageKey = NutritionErrorMapper.messageKey(for: error)
        }
        pendingDeleteRecordID = nil
        pendingDeleteHasAppleHealthID = false
    }

    func clearError() {
        errorMessageKey = nil
    }
}

@MainActor
final class NutritionEnergyBurnEditorViewModel: ObservableObject {
    @Published var state: NutritionEnergyBurnEditorState
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessageKey: String?

    private let energyBurnUseCase: NutritionEnergyBurnUseCase
    private let healthKitSyncUseCase: NutritionHealthKitSyncUseCase
    private let memberContextStore: MemberContextStore
    private let memberID: Int
    private let onSaved: () -> Void

    var isEditing: Bool { state.recordID != nil }

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        date: Date,
        existingRecord: SparkNutritionAPI.RemoteEnergyBurnRecord?,
        onSaved: @escaping () -> Void
    ) {
        self.energyBurnUseCase = dependencies.energyBurnUseCase
        self.healthKitSyncUseCase = dependencies.healthKitSyncUseCase
        self.memberContextStore = dependencies.memberContextStore
        self.memberID = memberID
        self.onSaved = onSaved
        if let existingRecord {
            self.state = NutritionEnergyBurnEditorState(
                recordID: existingRecord.id,
                burnedAt: existingRecord.burnedAt,
                energyKcal: NutritionFormatting.compactEnergy(existingRecord.energyKcal),
                activityType: existingRecord.activityType ?? "",
                durationMinutes: existingRecord.durationSeconds.map { String($0 / 60) } ?? "",
                note: existingRecord.note ?? ""
            )
        } else {
            self.state = NutritionEnergyBurnEditorState(
                recordID: nil,
                burnedAt: date,
                energyKcal: "",
                activityType: "",
                durationMinutes: "",
                note: ""
            )
        }
    }

    func clearError() {
        errorMessageKey = nil
    }

    func save() async -> Bool {
        guard isSaving == false else { return false }
        guard let energy = Double(state.energyKcal.trimmingCharacters(in: .whitespacesAndNewlines)), energy > 0 else {
            errorMessageKey = "nutrition.energy.error.invalid_energy"
            return false
        }

        isSaving = true
        errorMessageKey = nil
        defer { isSaving = false }

        let durationSeconds = Int(state.durationMinutes.trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 * 60 }

        do {
            let saved: SparkNutritionAPI.RemoteEnergyBurnRecord
            if let recordID = state.recordID {
                saved = try await energyBurnUseCase.updateRecord(
                    recordID: recordID,
                    request: SparkNutritionAPI.UpdateEnergyBurnRecordRequest(
                        burnedAt: state.burnedAt,
                        energyKcal: energy,
                        activityType: state.activityType,
                        durationSeconds: durationSeconds,
                        source: "manual",
                        note: state.note
                    )
                )
            } else {
                saved = try await energyBurnUseCase.createRecord(
                    SparkNutritionAPI.CreateEnergyBurnRecordRequest(
                        memberId: memberID,
                        burnedAt: state.burnedAt,
                        energyKcal: energy,
                        activityType: state.activityType.isEmpty ? "manual" : state.activityType,
                        durationSeconds: durationSeconds,
                        note: state.note
                    )
                )
            }

            if let member = memberContextStore.context.members.first(where: { $0.id == memberID }) {
                await healthKitSyncUseCase.writeEnergyBurnIfNeeded(member: member, record: saved)
            }

            NotificationCenter.default.post(name: .nutritionEnergyBurnDidChange, object: nil)
            onSaved()
            return true
        } catch {
            errorMessageKey = NutritionErrorMapper.messageKey(for: error)
            return false
        }
    }
}
