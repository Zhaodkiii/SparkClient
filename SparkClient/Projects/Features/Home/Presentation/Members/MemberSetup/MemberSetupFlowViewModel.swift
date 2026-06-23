import Foundation
import Combine
import SwiftUI

enum MemberSetupFlowMode {
    case create
    case maintain(Member)
}

/// 家庭成员新建引导流程视图模型
/// @MainActor：所有UI状态、业务逻辑强制运行在主线程
/// 职责：管理新增成员表单草稿、导航路由、健康模块勾选/存储、创建成员、弹窗/弹窗提示状态
@MainActor
final class MemberSetupFlowViewModel: ObservableObject {
    // MARK: - UI发布状态
    /// 新建成员填写草稿数据
    @Published var draft = MemberSetupDraft()
    /// 页面导航栈，控制流程多页面跳转
    @Published var navigationPath: [MemberSetupNavigationRoute] = []
    /// 创建成功后的家庭成员实体
    @Published var createdMember: Member?
    /// 用户勾选启用的健康功能模块集合
    @Published var selectedModules: Set<MemberSetupModule> = []
    /// 用户已完成填写的模块集合
    @Published var completedModules: Set<MemberSetupModule> = []
    /// 当前弹出的浮窗路由，nil代表无弹窗
    @Published var activeSheet: MemberSetupSheetRoute?
    /// 全局弹窗提示文案，赋值后弹出Alert
    @Published var alertMessage: String?
    /// 是否正在执行创建成员接口，用于按钮置灰、加载动画
    @Published var isSavingMember = false
    /// 是否正在持久化模块配置，防止并发重复写入
    @Published var isPersistingModules = false
    /// 是否正在读取成员已有模块配置
    @Published var isLoadingExistingModules = false
    /// 成员模块维护缓存（completeData + nutrition goals）
    @Published private(set) var moduleSetupCache: MemberModuleSetupCacheContext?
    /// 是否正在预加载成员模块缓存
    @Published var isPreloadingModuleCache = false

    // MARK: - 依赖注入
    /// 家庭成员本地/云端数据存储仓库
    let store: MemberContextStore
    /// 首页模块业务用例、依赖容器
    let homeDependencies: HomeFeatureDependencies
    /// 当前流程模式：创建新成员或维护已有成员模块。
    let mode: MemberSetupFlowMode

    private var didLoadExistingModules = false
    private var moduleSetupPreloadTask: Task<Void, Never>?
    private var completeDataLoadTask: Task<SparkMedicalSyncAPI.RemoteMemberCompleteData?, Never>?
    private var nutritionGoalLoadTask: Task<SparkNutritionAPI.RemoteNutritionGoalState?, Never>?

    /// 初始化，注入数据仓库与业务依赖，支持单元测试自定义传入
    init(
        mode: MemberSetupFlowMode = .create,
        store: MemberContextStore,
        homeDependencies: HomeFeatureDependencies
    ) {
        self.mode = mode
        self.store = store
        self.homeDependencies = homeDependencies

        if case .maintain(let member) = mode {
            createdMember = member
            draft = MemberSetupDraft(
                name: member.name,
                birthDate: member.birthDate,
                relationshipCode: member.relationship,
                gender: member.gender
            )
            navigationPath = [.modules]
        }
    }

    // MARK: - 页面跳转校验计算属性
    /// 基础信息页是否可下一步：姓名非空
    var canAdvanceFromBasicInfo: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 关系性别页是否可下一步：当前性别符合可选规范
    var canAdvanceFromRelationship: Bool {
        MemberRelationshipCatalog.isSelectableGender(draft.gender)
    }

    /// 是否允许完成整个创建流程：至少选中一个模块、无模块存储操作中
    var canFinish: Bool {
        !selectedModules.filter(\.isVisibleInSetup).isEmpty && !isPersistingModules && !isLoadingExistingModules
    }

    // MARK: - 成员模块缓存

    func moduleSetupCache(for memberID: Int) -> MemberModuleSetupCacheContext? {
        guard moduleSetupCache?.memberID == memberID else { return nil }
        return moduleSetupCache
    }

    func preloadModuleSetupCacheIfNeeded(forceRefresh: Bool = false) async {
        guard let member = createdMember else { return }

        if forceRefresh == false,
           let cache = moduleSetupCache,
           cache.memberID == member.id,
           cache.completeData != nil {
            homeDependencies.logger.info(
                "成员模块缓存：命中已有缓存 memberID=\(member.id)",
                module: .medical
            )
            return
        }

        if let existingTask = moduleSetupPreloadTask {
            await existingTask.value
            return
        }

        let task = Task { @MainActor in
            isPreloadingModuleCache = true
            defer {
                isPreloadingModuleCache = false
                moduleSetupPreloadTask = nil
            }

            homeDependencies.logger.info(
                "成员模块缓存：开始预加载 memberID=\(member.id)",
                module: .medical
            )

            var context = moduleSetupCache?.memberID == member.id
                ? (moduleSetupCache ?? MemberModuleSetupCacheContext(memberID: member.id))
                : MemberModuleSetupCacheContext(memberID: member.id)
            moduleSetupCache = context

            let loadedCompleteData = await loadCompleteData(memberID: member.id, forceRefresh: forceRefresh)

            context.completeData = loadedCompleteData ?? context.completeData
            await syncNutritionGoalState(into: &context, memberID: member.id, forceRefresh: forceRefresh)
            context.loadedAt = Date()
            moduleSetupCache = context

            if let loadedCompleteData = context.completeData {
                applyModuleSettingsFromCache(loadedCompleteData)
                homeDependencies.logger.info(
                    "成员模块缓存：completeData 加载成功 memberID=\(member.id) symptoms=\(loadedCompleteData.symptoms?.count ?? 0) medicationPlans=\(loadedCompleteData.medicationPlans?.count ?? 0) surgeries=\(loadedCompleteData.surgeries?.count ?? 0) moduleSettings=\(loadedCompleteData.memberModuleSettings?.count ?? 0) hasProfile=\(loadedCompleteData.memberMedicalProfile == nil ? 0 : 1) hasNutritionGoalState=\(loadedCompleteData.nutritionGoalState == nil ? 0 : 1)",
                    module: .medical
                )
            }
        }
        moduleSetupPreloadTask = task
        await task.value
    }

    /// 显式刷新缓存；仅用户重试或保存后需要最新数据时调用。
    func refreshModuleSetupCacheIfNeeded(force: Bool = false) async {
        guard let member = createdMember else { return }
        guard force || shouldRefreshModuleSetupCache else { return }

        homeDependencies.logger.info(
            "成员模块缓存：后台刷新 memberID=\(member.id)",
            module: .medical
        )

        let loadedCompleteData = await loadCompleteData(memberID: member.id, forceRefresh: true)

        guard var context = moduleSetupCache, context.memberID == member.id else { return }
        if let loadedCompleteData {
            context.completeData = loadedCompleteData
            applyModuleSettingsFromCache(loadedCompleteData)
        }
        await syncNutritionGoalState(into: &context, memberID: member.id, forceRefresh: true)
        context.loadedAt = Date()
        moduleSetupCache = context
    }

    private func syncNutritionGoalState(
        into context: inout MemberModuleSetupCacheContext,
        memberID: Int,
        forceRefresh: Bool
    ) async {
        if let embedded = context.completeData?.nutritionGoalState {
            context.nutritionGoalState = embedded
            homeDependencies.logger.info(
                "成员模块缓存：completeData 内含 nutritionGoalState memberID=\(memberID) hasGoal=\(embedded.goal == nil ? 0 : 1)",
                module: .medical
            )
            return
        }

        if forceRefresh == false, context.nutritionGoalState != nil {
            return
        }

        guard let supplemented = await loadNutritionGoalState(memberID: memberID, forceRefresh: forceRefresh) else {
            return
        }

        context.nutritionGoalState = supplemented
        if var completeData = context.completeData {
            completeData.nutritionGoalState = supplemented
            context.completeData = completeData
        }
        homeDependencies.logger.info(
            "成员模块缓存：nutritionGoalState 补请求成功 memberID=\(memberID) hasGoal=\(supplemented.goal == nil ? 0 : 1)",
            module: .medical
        )
    }

    private var shouldRefreshModuleSetupCache: Bool {
        guard let loadedAt = moduleSetupCache?.loadedAt else { return true }
        return Date().timeIntervalSince(loadedAt) > 300
    }

    func patchCompleteData(_ transform: (inout SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void) {
        guard var context = moduleSetupCache,
              var completeData = context.completeData else { return }
        transform(&completeData)
        context.completeData = completeData
        moduleSetupCache = context
    }

    func patchNutritionGoalState(_ state: SparkNutritionAPI.RemoteNutritionGoalState?) {
        guard var context = moduleSetupCache else { return }
        context.nutritionGoalState = state
        if var completeData = context.completeData {
            completeData.nutritionGoalState = state
            context.completeData = completeData
        }
        moduleSetupCache = context
    }

    private func loadCompleteData(memberID: Int, forceRefresh: Bool) async -> SparkMedicalSyncAPI.RemoteMemberCompleteData? {
        if forceRefresh == false, let task = completeDataLoadTask {
            return await task.value
        }

        let task = Task<SparkMedicalSyncAPI.RemoteMemberCompleteData?, Never> {
            defer { completeDataLoadTask = nil }
            do {
                let data = try await homeDependencies.medicalQueryAPI.fetchMemberCompleteData(memberID: memberID)
                if var context = moduleSetupCache, context.memberID == memberID {
                    context.completeDataLoadError = nil
                    moduleSetupCache = context
                }
                return data
            } catch {
                homeDependencies.logger.warning(
                    "成员模块缓存：completeData 加载失败 memberID=\(memberID) error=\(error.localizedDescription)",
                    module: .medical
                )
                if var context = moduleSetupCache, context.memberID == memberID {
                    context.completeDataLoadError = error.localizedDescription
                    moduleSetupCache = context
                }
                return moduleSetupCache?.completeData
            }
        }
        completeDataLoadTask = task
        return await task.value
    }

    private func loadNutritionGoalState(memberID: Int, forceRefresh: Bool) async -> SparkNutritionAPI.RemoteNutritionGoalState? {
        if forceRefresh == false, let task = nutritionGoalLoadTask {
            return await task.value
        }

        let task = Task<SparkNutritionAPI.RemoteNutritionGoalState?, Never> {
            defer { nutritionGoalLoadTask = nil }
            do {
                let state = try await homeDependencies.nutritionDependencies.goalUseCase.loadGoalState(memberID: memberID)
                if var context = moduleSetupCache, context.memberID == memberID {
                    context.nutritionGoalLoadError = nil
                    moduleSetupCache = context
                }
                return state
            } catch {
                homeDependencies.logger.warning(
                    "成员模块缓存：nutritionGoalState 加载失败 memberID=\(memberID) error=\(error.localizedDescription)",
                    module: .medical
                )
                if var context = moduleSetupCache, context.memberID == memberID {
                    context.nutritionGoalLoadError = error.localizedDescription
                    moduleSetupCache = context
                }
                return moduleSetupCache?.nutritionGoalState
            }
        }
        nutritionGoalLoadTask = task
        return await task.value
    }

    private func applyModuleSettingsFromCache(_ completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData) {
        let settings = completeData.memberModuleSettings ?? []
        guard settings.isEmpty == false else { return }

        let visibleSettings = settings.compactMap { setting -> (MemberSetupModule, SparkMedicalSyncAPI.RemoteMemberModuleSetting)? in
            guard let module = MemberSetupModule(rawValue: setting.moduleCode), module.isVisibleInSetup else {
                return nil
            }
            return (module, setting)
        }
        selectedModules = Set(visibleSettings.filter { $0.1.isEnabled }.map { $0.0 })
        completedModules = Set(visibleSettings.filter { $0.1.isEnabled && $0.1.isCompleted }.map { $0.0 })
        didLoadExistingModules = true
        isLoadingExistingModules = false
    }

    // MARK: - 对外业务方法
    /// 执行创建家庭成员主流程
    /// - Returns: 创建成功返回true，失败/校验不通过返回false
    func createMember() async -> Bool {
        // 前置校验：性别关系页未通过、正在保存则直接拦截
        guard canAdvanceFromRelationship, !isSavingMember else { return false }
        isSavingMember = true
        defer { isSavingMember = false } // 无论成功失败，结束后关闭加载状态

        // 调用仓库创建成员
        let member = await store.addMember(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            relationship: draft.relationshipCode,
            gender: draft.gender,
            birthDate: draft.birthDate
        )
        guard let member else {
            alertMessage = L10n.text("home.members.add.failed")
            return false
        }
        createdMember = member
        return true
    }

    /// 标记指定模块为已完成，并加入完成集合
    /// - Parameters:
    ///   - module: 目标模块
    ///   - summaryText: 模块完成后的展示摘要
    func markModuleCompleted(_ module: MemberSetupModule, summaryText: String) async {
        completedModules.insert(module)
        selectedModules.insert(module)
    }

    /// 标记模块已选中（首页展示），但不计入完成。
    func markModuleSelected(_ module: MemberSetupModule) async {
        selectedModules.insert(module)
        completedModules.remove(module)
        guard let member = createdMember else { return }
        do {
            let saved = try await homeDependencies.memberModuleSetupUseCase.markModuleSelected(
                memberID: member.id,
                module: module
            )
            patchCompleteData { MemberModuleSetupCompleteDataPatcher.upsertModuleSetting(saved, into: &$0) }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// 保存分组完成进度，并刷新模块选中/完成状态。
    func markSectionCompleted(
        _ module: MemberSetupModule,
        sectionCode: String,
        summaryText: String
    ) async {
        selectedModules.insert(module)
        guard let member = createdMember else { return }
        do {
            let saved = try await homeDependencies.memberModuleSetupUseCase.saveSectionProgress(
                memberID: member.id,
                module: module,
                sectionCode: sectionCode,
                status: .completed,
                summary: summaryText
            )
            patchCompleteData { MemberModuleSetupCompleteDataPatcher.upsertModuleSetting(saved, into: &$0) }
            if saved.isCompleted {
                completedModules.insert(module)
            } else {
                completedModules.remove(module)
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// 打开对应模块的汇总页
    func openModuleSummary(for module: MemberSetupModule) {
        selectedModules.insert(module)
        switch module {
        case .medical:
            navigationPath.append(.medicalSummary)
        case .nutrition:
            navigationPath.append(.nutritionSummary)
        case .dailyHealth:
            activeSheet = .lifestyle
        }
    }

    /// 打开模块维护 Sheet
    func openSheet(for module: MemberSetupModule, entryMode: MedicalSetupEntryMode? = nil) {
        selectedModules.insert(module)
        switch module {
        case .medical:
            activeSheet = .medical(entryMode ?? .full)
        case .nutrition:
            activeSheet = .nutrition(.full)
        case .dailyHealth:
            activeSheet = .lifestyle
        }
    }

    func openMedicalSheet(mode: MedicalSetupEntryMode) {
        activeSheet = .medical(mode)
    }

    func openNutritionSheet(mode: NutritionSetupEntryMode) {
        activeSheet = .nutrition(mode)
    }

    /// 维护模式进入模块页时，读取成员已有模块配置并回填勾选/完成状态。
    func loadExistingModuleSettingsIfNeeded() async {
        guard case .maintain = mode else { return }
        guard !didLoadExistingModules, let member = createdMember else { return }

        if let completeData = moduleSetupCache?.completeData,
           completeData.memberModuleSettings?.isEmpty == false {
            applyModuleSettingsFromCache(completeData)
            return
        }

        didLoadExistingModules = true
        isLoadingExistingModules = true
        defer { isLoadingExistingModules = false }

        do {
            let settings = try await homeDependencies.memberModuleSetupUseCase.loadModuleSettings(memberID: member.id)
            let visibleSettings = settings.compactMap { setting -> (MemberSetupModule, SparkMedicalSyncAPI.RemoteMemberModuleSetting)? in
                guard let module = MemberSetupModule(rawValue: setting.moduleCode), module.isVisibleInSetup else {
                    return nil
                }
                return (module, setting)
            }
            selectedModules = Set(visibleSettings.filter { $0.1.isEnabled }.map { $0.0 })
            completedModules = Set(visibleSettings.filter { $0.1.isEnabled && $0.1.isCompleted }.map { $0.0 })
            patchCompleteData { completeData in
                completeData.memberModuleSettings = settings
            }
        } catch {
            alertMessage = L10n.text("member.module.selection.load_failed", fallback: "模块配置加载失败，请稍后重试")
        }
    }

    /// 流程收尾：保存当前选中模块状态
    /// - Returns: 存储流程无异常返回true
    func finish() async -> Bool {
        guard let member = createdMember else { return false }
        guard !isPersistingModules else { return false }
        isPersistingModules = true
        defer { isPersistingModules = false }

        do {
            for module in selectedModules where module.isVisibleInSetup {
                let isCompleted = completedModules.contains(module)
                let saved = try await homeDependencies.memberModuleSetupUseCase.saveModuleSetting(
                    memberID: member.id,
                    moduleCode: module.rawValue,
                    isEnabled: true,
                    isCompleted: isCompleted,
                    displayOrder: module.displayOrder,
                    summaryText: isCompleted ? module.title : "",
                    completedAt: isCompleted ? Date() : nil
                )
                patchCompleteData { MemberModuleSetupCompleteDataPatcher.upsertModuleSetting(saved, into: &$0) }
            }
            return true
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }
}
