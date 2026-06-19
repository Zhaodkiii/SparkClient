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

    // MARK: - 依赖注入
    /// 家庭成员本地/云端数据存储仓库
    let store: MemberContextStore
    /// 首页模块业务用例、依赖容器
    let homeDependencies: HomeFeatureDependencies
    /// 当前流程模式：创建新成员或维护已有成员模块。
    let mode: MemberSetupFlowMode

    private var didLoadExistingModules = false

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
    /// 基础信息页是否可下一步：姓名非空 + 已选择出生日期
    var canAdvanceFromBasicInfo: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.birthDate != nil
    }

    /// 关系性别页是否可下一步：当前性别符合可选规范
    var canAdvanceFromRelationship: Bool {
        MemberRelationshipCatalog.isSelectableGender(draft.gender)
    }

    /// 是否允许完成整个创建流程：至少完成一个模块、无模块存储操作中
    var canFinish: Bool {
        !completedModules.filter(\.isVisibleInSetup).isEmpty && !isPersistingModules && !isLoadingExistingModules
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

    /// 维护模式进入模块页时，读取成员已有模块配置并回填勾选/完成状态。
    func loadExistingModuleSettingsIfNeeded() async {
        guard case .maintain = mode else { return }
        guard !didLoadExistingModules, let member = createdMember else { return }
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
        } catch {
            alertMessage = L10n.text("member.module.selection.load_failed", fallback: "模块配置加载失败，请稍后重试")
        }
    }

    /// 流程收尾：模块开通只由各模块「保存/提交」动作完成，这里不补写待完善状态
    /// - Returns: 存储流程无异常返回true
    func finish() async -> Bool {
        guard createdMember != nil else { return false }
        guard !isPersistingModules else { return false }
        isPersistingModules = true
        defer { isPersistingModules = false }
        return true
    }

    /// 打开对应模块的详情弹窗
    /// - Parameter module: 点击的功能模块
    func openSheet(for module: MemberSetupModule) {
        switch module {
        case .medical:
            activeSheet = .medical
        case .nutrition:
            activeSheet = .nutrition
        case .dailyHealth:
            activeSheet = .lifestyle
        }
    }

}
