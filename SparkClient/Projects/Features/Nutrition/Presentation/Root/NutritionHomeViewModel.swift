import Combine
import Foundation

struct NutritionFeatureDependencies {
    let dashboardUseCase: NutritionDashboardUseCase
    let mealRecordUseCase: NutritionMealRecordUseCase
    let searchUseCase: NutritionSearchUseCase
    let healthKitSyncUseCase: NutritionHealthKitSyncUseCase
    let energyBurnUseCase: NutritionEnergyBurnUseCase
    let recognitionPipeline: any NutritionRecognitionPipeline
    let configCenter: AIConfigCenter
    let memberContextStore: MemberContextStore
    let notificationStore: NotificationStore
    let logger: Logger
}

@MainActor
final class NutritionHomeViewModel: ObservableObject {
    @Published private(set) var state = NutritionHomeState()

    private let dashboardUseCase: NutritionDashboardUseCase
    private let healthKitSyncUseCase: NutritionHealthKitSyncUseCase
    private let memberContextStore: MemberContextStore
    private let logger: Logger

    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?

    init(dependencies: NutritionFeatureDependencies) {
        self.dashboardUseCase = dependencies.dashboardUseCase
        self.healthKitSyncUseCase = dependencies.healthKitSyncUseCase
        self.memberContextStore = dependencies.memberContextStore
        self.logger = dependencies.logger
        self.state.selectedMemberID = memberContextStore.context.selectedMemberID
    }

    var selectedMember: Member? {
        guard let memberID = state.selectedMemberID else { return nil }
        return memberContextStore.context.members.first(where: { $0.id == memberID })
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        loadTask?.cancel()
        loadTask = Task { await performReload() }
        await loadTask?.value
    }

    func setSelectedDate(_ date: Date) {
        state.selectedDate = date
        Task { await reload() }
    }

    func syncMemberSelection(_ memberID: Int?) {
        guard state.selectedMemberID != memberID else { return }
        state.selectedMemberID = memberID
        Task { await reload() }
    }

    private func performReload() async {
        guard let memberID = resolvedMemberID() else {
            state.loadState = .error(messageKey: "nutrition.error.invalid_member")
            return
        }

        state.selectedMemberID = memberID
        state.loadState = .loading

        do {
            if let member = memberContextStore.context.members.first(where: { $0.id == memberID }) {
                await healthKitSyncUseCase.syncTodayIfNeeded(member: member, date: state.selectedDate)
            }

            let dashboard = try await dashboardUseCase.loadDashboard(
                memberID: memberID,
                date: state.selectedDate
            )
            guard Task.isCancelled == false else { return }
            state.loadState = .content(dashboard)
        } catch {
            guard Task.isCancelled == false else { return }
            let messageKey = NutritionErrorMapper.messageKey(for: error)
            logger.warning(
                "饮食营养看板加载失败 memberID=\(memberID) error=\(error.localizedDescription)",
                module: .nutrition
            )
            state.loadState = .error(messageKey: messageKey)
        }
    }

    private func resolvedMemberID() -> Int? {
        if let selected = state.selectedMemberID,
           memberContextStore.context.members.contains(where: { $0.id == selected }) {
            return selected
        }
        return memberContextStore.context.selectedMemberID
            ?? memberContextStore.context.members.first?.id
    }
}

@MainActor
final class NutritionSummaryDetailViewModel: ObservableObject {
    @Published private(set) var detail: NutritionSummaryDetailViewData?
    @Published var selectedMeal: NutritionMealType = .breakfast
    @Published private(set) var loadState: NutritionHomeLoadState = .idle

    private let dashboardUseCase: NutritionDashboardUseCase
    private let memberID: Int
    private let date: Date
    private var dashboard: NutritionDashboardViewData?

    init(
        dashboardUseCase: NutritionDashboardUseCase,
        memberID: Int,
        date: Date,
        initialDashboard: NutritionDashboardViewData? = nil
    ) {
        self.dashboardUseCase = dashboardUseCase
        self.memberID = memberID
        self.date = date
        self.dashboard = initialDashboard
        if let initialDashboard {
            self.detail = NutritionViewDataMapper.summaryDetail(from: initialDashboard)
            self.loadState = .content(initialDashboard)
        }
    }

    func loadIfNeeded() async {
        if detail != nil { return }
        await reload()
    }

    func reload() async {
        loadState = .loading
        do {
            let loaded = try await dashboardUseCase.loadDashboardDetail(memberID: memberID, date: date)
            dashboard = try await dashboardUseCase.loadDashboard(memberID: memberID, date: date)
            detail = loaded
            loadState = .content(dashboard!)
        } catch {
            loadState = .error(messageKey: NutritionErrorMapper.messageKey(for: error))
        }
    }

    var selectedMealSection: NutritionMealSectionViewData? {
        dashboard?.meals.first(where: { $0.mealType == selectedMeal })
    }

    var selectedMealMacroProgress: NutritionMacroProgressCardData? {
        selectedMealSection.map(NutritionViewDataMapper.macroProgressCard)
    }

    var selectedMealRatioChart: NutritionMacroRatioChartData? {
        selectedMealSection.map(NutritionViewDataMapper.macroRatioChart)
    }
}

@MainActor
final class NutritionDetailViewModel: ObservableObject {
    @Published private(set) var groups: [NutritionMealGroupViewData] = []
    @Published private(set) var records: [SparkNutritionAPI.RemoteMealRecord] = []
    @Published private(set) var loadState: NutritionHomeLoadState = .idle

    private let mealRecordUseCase: NutritionMealRecordUseCase
    let memberID: Int
    let date: Date

    init(mealRecordUseCase: NutritionMealRecordUseCase, memberID: Int, date: Date) {
        self.mealRecordUseCase = mealRecordUseCase
        self.memberID = memberID
        self.date = date
    }

    var hasEditableRecords: Bool {
        records.contains { $0.mealFoods.isEmpty == false }
    }

    func record(for row: NutritionMealFoodRowViewData) -> SparkNutritionAPI.RemoteMealRecord? {
        records.first { $0.id == row.recordID }
    }

    func loadIfNeeded() async {
        guard groups.isEmpty else { return }
        await reload()
    }

    func reload() async {
        loadState = .loading
        do {
            let response = try await mealRecordUseCase.fetchMealRecordPage(memberID: memberID, date: date)
            records = response.records
            groups = NutritionViewDataMapper.mealGroups(from: response)
            loadState = .content(
                NutritionDashboardViewData(
                    memberID: memberID,
                    date: date,
                    consumedEnergyKcal: 0,
                    remainingEnergyKcal: 0,
                    burnedEnergyKcal: 0,
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
}

@MainActor
final class NutritionMealDetailViewModel: ObservableObject {
    @Published private(set) var detail: NutritionMealDetailViewData?
    @Published private(set) var loadState: NutritionHomeLoadState = .idle
    @Published private(set) var errorMessageKey: String?

    private let mealRecordUseCase: NutritionMealRecordUseCase
    private let memberID: Int
    private let date: Date
    let mealType: NutritionMealType

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        date: Date,
        mealType: NutritionMealType
    ) {
        self.mealRecordUseCase = dependencies.mealRecordUseCase
        self.memberID = memberID
        self.date = date
        self.mealType = mealType
    }

    func loadIfNeeded() async {
        guard detail == nil else { return }
        await reload()
    }

    func reload() async {
        loadState = .loading
        do {
            let loaded = try await mealRecordUseCase.loadMealDetail(
                memberID: memberID,
                date: date,
                mealType: mealType
            )
            detail = loaded
            loadState = .content(
                NutritionDashboardViewData(
                    memberID: memberID,
                    date: date,
                    consumedEnergyKcal: loaded.overview.energyKcal,
                    remainingEnergyKcal: 0,
                    burnedEnergyKcal: 0,
                    targetEnergyKcal: loaded.macroProgress.energy.target,
                    intakeProgress: 0,
                    overview: loaded.overview,
                    carbohydrate: loaded.macroProgress.carbohydrate,
                    protein: loaded.macroProgress.protein,
                    fat: loaded.macroProgress.fat,
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

    func clearError() {
        errorMessageKey = nil
    }
}
