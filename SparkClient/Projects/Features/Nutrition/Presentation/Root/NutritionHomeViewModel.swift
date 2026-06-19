import Combine
import Foundation

// MARK: - 营养模块 Presentation 层 ViewModel
//
// 本文件包含营养 Tab 首页及若干子页面的 ViewModel，负责：
// - 驱动 SwiftUI 状态（@Published / loadState）
// - 调用 UseCase 加载数据并映射为 ViewData
// - 协调成员切换、日期切换与 HealthKit 同步时机
//
// 所有 ViewModel 标记 @MainActor，保证 UI 状态更新在主线程。

// MARK: - 依赖注入容器

/// 营养功能模块的统一依赖包，由 Feature 入口组装后注入各 ViewModel / Coordinator
struct NutritionFeatureDependencies {
    let dashboardUseCase: NutritionDashboardUseCase
    let mealRecordUseCase: NutritionMealRecordUseCase
    let searchUseCase: NutritionSearchUseCase
    let healthKitSyncUseCase: NutritionHealthKitSyncUseCase
    let energyBurnUseCase: NutritionEnergyBurnUseCase
    let goalUseCase: NutritionGoalUseCase
    let recognitionPipeline: any NutritionRecognitionPipeline
    let configCenter: AIConfigCenter
    let memberContextStore: MemberContextStore
    let notificationStore: NotificationStore
    let logger: Logger
}

// MARK: - 营养首页

/// 营养 Tab 首页 ViewModel：展示某日看板（摄入、目标、各餐次入口）
@MainActor
final class NutritionHomeViewModel: ObservableObject {
    /// 首页聚合状态：选中成员/日期、加载态、看板内容等
    @Published private(set) var state = NutritionHomeState()

    private let dashboardUseCase: NutritionDashboardUseCase
    private let healthKitSyncUseCase: NutritionHealthKitSyncUseCase
    private let memberContextStore: MemberContextStore
    private let logger: Logger

    /// 是否已完成首次加载（避免 onAppear 重复请求）
    private var hasLoaded = false
    /// 当前进行中的 reload Task，新 reload 会先 cancel 旧任务，防止竞态覆盖 UI
    private var loadTask: Task<Void, Never>?

    init(dependencies: NutritionFeatureDependencies) {
        self.dashboardUseCase = dependencies.dashboardUseCase
        self.healthKitSyncUseCase = dependencies.healthKitSyncUseCase
        self.memberContextStore = dependencies.memberContextStore
        self.logger = dependencies.logger
        self.state.selectedMemberID = memberContextStore.context.selectedMemberID
    }

    /// 当前选中的成员实体（从 MemberContextStore 解析）
    var selectedMember: Member? {
        guard let memberID = state.selectedMemberID else { return nil }
        return memberContextStore.context.members.first(where: { $0.id == memberID })
    }

    /// 首次进入页面时加载；后续切 Tab 回来不会重复触发
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    /// 强制刷新：取消旧任务并等待新任务完成
    func reload() async {
        loadTask?.cancel()
        loadTask = Task { await performReload() }
        await loadTask?.value
    }

    /// 用户切换日历日期后更新 state 并触发 reload
    func setSelectedDate(_ date: Date) {
        state.selectedDate = date
        Task { await reload() }
    }

    /// 全局成员选择变化时同步（如从其他 Tab 切换成员）
    func syncMemberSelection(_ memberID: Int?) {
        guard state.selectedMemberID != memberID else { return }
        state.selectedMemberID = memberID
        Task { await reload() }
    }

    /// 实际加载流程：
    /// 1. 解析有效 memberID
    /// 2. 本人成员时先 sync HealthKit 外部数据到服务端（失败不阻塞看板）
    /// 3. 拉取看板 ViewData
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

    /// 成员 ID 解析优先级：state 内选中且仍存在于成员列表 → 全局选中 → 列表第一个
    private func resolvedMemberID() -> Int? {
        if let selected = state.selectedMemberID,
           memberContextStore.context.members.contains(where: { $0.id == selected }) {
            return selected
        }
        return memberContextStore.context.selectedMemberID
            ?? memberContextStore.context.members.first?.id
    }
}

// MARK: - 营养汇总详情页

/// 「营养详情」页：展示全日宏量进度，并可切换餐次查看分餐数据
@MainActor
final class NutritionSummaryDetailViewModel: ObservableObject {
    @Published private(set) var detail: NutritionSummaryDetailViewData?
    /// 当前选中的餐次 Tab（早餐/午餐等）
    @Published var selectedMeal: NutritionMealType = .breakfast
    @Published private(set) var loadState: NutritionHomeLoadState = .idle

    private let dashboardUseCase: NutritionDashboardUseCase
    private let memberID: Int
    private let date: Date
    /// 完整看板数据，供分餐 Section 与图表计算使用
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
        // 从首页传入看板时可免网络请求，直接展示
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

    /// 当前选中餐次在看板 meals 数组中的 Section
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

// MARK: - 全日用餐列表页

/// 某日全部用餐记录列表（按餐次分组），供编辑、批量操作等场景
@MainActor
final class NutritionDetailViewModel: ObservableObject {
    @Published private(set) var groups: [NutritionMealGroupViewData] = []
    /// 原始 Remote 记录，编辑/删除时需要完整 mealFoods 与 intakes
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

    /// 是否存在含食物的记录（空记录不可编辑份量）
    var hasEditableRecords: Bool {
        records.contains { $0.mealFoods.isEmpty == false }
    }

    /// 根据列表行反查完整 RemoteMealRecord
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
            // loadState 复用 NutritionHomeLoadState.content，此处用占位 Dashboard 表示「已成功」
            // 本页 UI 主要绑定 groups/records，不依赖占位字段
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

// MARK: - 单餐详情页

/// 某一餐次（如午餐）的详情：该餐食物列表、营养小计、宏量进度
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
            // 用 loaded 中的 overview / macroProgress 填充 content，供共享组件复用
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
