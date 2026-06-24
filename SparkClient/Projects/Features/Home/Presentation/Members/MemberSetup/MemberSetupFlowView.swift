import SwiftUI

/// 新增家庭成员完整引导流程页面
/// 串联「姓名生日 → 亲属性别 → 创建成员 → 健康模块配置」多步骤导航流程
/// 支持医疗/饮食/日常健康模块弹窗编辑、流程退出、创建完成回调
struct MemberSetupFlowView: View {
    /// 新建成员流程视图模型，持有表单草稿、导航路由、加载状态
    @StateObject private var viewModel: MemberSetupFlowViewModel
    /// 页面退出环境变量
    @Environment(\.dismiss) private var dismiss
    /// 页面出现时执行的异步回调，可为nil
    let onAppearAction: MainActorAsyncVoidAction?
    /// 成员创建成功后的外部回调，回传新建成员实体
    let onMemberCreated: ((Member) -> Void)?

    /// 初始化引导流程页面
    /// - Parameters:
    ///   - mode: 流程模式，默认新建成员create
    ///   - store: 家庭成员上下文仓库
    ///   - homeDependencies: 首页全量业务依赖容器
    ///   - onAppearAction: 页面加载前置异步动作
    ///   - onMemberCreated: 成员创建完成回调
    init(
        mode: MemberSetupFlowMode = .create,
        store: MemberContextStore,
        homeDependencies: HomeFeatureDependencies,
        onAppearAction: MainActorAsyncVoidAction? = nil,
        onMemberCreated: ((Member) -> Void)? = nil
    ) {
        // 初始化流程视图模型，注入流程模式与业务依赖
        _viewModel = StateObject(wrappedValue: MemberSetupFlowViewModel(mode: mode, store: store, homeDependencies: homeDependencies))
        self.onAppearAction = onAppearAction
        self.onMemberCreated = onMemberCreated
    }

    var body: some View {
        // 兼容型导航容器，绑定流程导航栈，启用传统栈样式
        CompatibleRouteNavigationContainer(path: $viewModel.navigationPath, legacyStackStyle: true) {
            // 初始首页：姓名+生日填写步骤
            MemberNameBirthStepView(
                draft: $viewModel.draft,
                canAdvance: viewModel.canAdvanceFromBasicInfo,
                onNext: { viewModel.navigationPath.append(.birthDate) }
            )
        } destination: { route in
            // 导航路由分支分发，渲染对应步骤页面
            switch route {
            case .birthDate:
                // 生日选择步骤
                MemberBirthDateStepView(
                    draft: $viewModel.draft,
                    onNext: { viewModel.navigationPath.append(.relationship) },
                    onSkip: { viewModel.navigationPath.append(.relationship) }
                )
            case .relationship:
                // 亲属关系+性别选择步骤，点击下一步执行创建成员接口
                MemberRelationshipGenderStepView(
                    draft: $viewModel.draft,
                    canAdvance: viewModel.canAdvanceFromRelationship,
                    isLoading: viewModel.isSavingMember,
                    onBack: { pop() },
                    onNext: {
                        Task {
                            // 创建成员成功后跳转到模块选择页
                            if await viewModel.createMember() {
                                viewModel.navigationPath = [.modules]
                            }
                        }
                    }
                )
            case .modules:
                // 健康功能模块勾选配置页面
                MemberModuleSetupView(
                    viewModel: viewModel,
                    onOpenModule: { module in
                        viewModel.openSheet(for: module)
                    },
                    onDoneAction: MainActorAsyncVoidAction {
                        // 点击完成：持久化模块配置，回调外部并关闭流程
                        if await viewModel.finish() {
                            if let member = viewModel.createdMember {
                                onMemberCreated?(member)
                            }
                            dismiss()
                        }
                    },
                    onSkipAction: MainActorAsyncVoidAction {
                        // 跳过模块配置：直接保存默认配置后退出
                        if await viewModel.finish() {
                            if let member = viewModel.createdMember {
                                onMemberCreated?(member)
                            }
                            dismiss()
                        }
                    }
                )
            case .medicalSummary:
                // 医疗模块信息汇总预览页
                if let member = viewModel.createdMember {
                    MemberMedicalModuleSummaryView(member: member, flowViewModel: viewModel)
                } else {
                    Text(L10n.text("member.setup.flow.member_missing"))
                        .foregroundStyle(.secondary)
                }
            case .nutritionSummary:
                // 饮食营养模块汇总预览页
                if let member = viewModel.createdMember {
                    MemberNutritionModuleSummaryView(member: member, flowViewModel: viewModel)
                } else {
                    Text(L10n.text("member.setup.flow.member_missing"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        // 统一流程左上角退出工具栏
        .memberSetupFlowDismissToolbar(onDismiss: { dismiss() })
        // 模块编辑浮窗分发
        .sheet(item: $viewModel.activeSheet) { route in
            switch route {
            case .medical(let entryMode):
                // 医疗模块编辑弹窗
                MemberMedicalSetupSheetView(
                    member: viewModel.createdMember,
                    medicalQueryAPI: viewModel.homeDependencies.medicalQueryAPI,
                    setupUseCase: viewModel.homeDependencies.memberModuleSetupUseCase,
                    homeDependencies: viewModel.homeDependencies,
                    // 预加载缓存的医疗完整数据，避免重复请求
                    preloadedCompleteData: viewModel.moduleSetupCache(for: viewModel.createdMember?.id ?? -1)?.completeData,
                    preloadedNutritionGoalState: viewModel.moduleSetupCache(for: viewModel.createdMember?.id ?? -1)?.completeData?.nutritionGoalState
                        ?? viewModel.moduleSetupCache(for: viewModel.createdMember?.id ?? -1)?.nutritionGoalState,
                    onCompleteDataPatch: viewModel.patchCompleteData,
                    entryMode: entryMode
                ) { summary in
                    // 完整填写模式下标记医疗模块为已完成
                    Task {
                        if entryMode == .full {
                            await viewModel.markModuleCompleted(.medical, summaryText: summary)
                        }
                    }
                } onSectionCompleted: { mode, summary in
                    // 单小节填写完成回调
                    Task {
                        if let sectionCode = mode.sectionCode {
                            await viewModel.markSectionCompleted(.medical, sectionCode: sectionCode, summaryText: summary)
                        }
                    }
                }
            case .nutrition(let entryMode):
                // 饮食营养模块编辑弹窗
                MemberNutritionSetupSheetView(
                    member: viewModel.createdMember,
                    goalUseCase: viewModel.homeDependencies.nutritionDependencies.goalUseCase,
                    setupUseCase: viewModel.homeDependencies.memberModuleSetupUseCase,
                    entryMode: entryMode
                ) { summary in
                    Task {
                        if entryMode == .full {
                            await viewModel.markModuleCompleted(.nutrition, summaryText: summary)
                        }
                    }
                } onSectionCompleted: { mode, summary in
                    Task {
                        if let sectionCode = mode.sectionCode {
                            await viewModel.markSectionCompleted(.nutrition, sectionCode: sectionCode, summaryText: summary)
                        }
                    }
                }
            case .lifestyle:
                // 日常健康预留模块弹窗
                MemberLifestyleSetupSheetView(
                    onCompletedAction: MainActorAsyncVoidAction {
                        await viewModel.markModuleCompleted(.dailyHealth, summaryText: "日常健康模块预留")
                    }
                )
            }
        }
        // 全局错误提示弹窗
        .alert(
            L10n.text("common.ok"),
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            )
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {
                viewModel.alertMessage = nil
            }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        // 页面首次加载执行预缓存、加载模块配置、页面入场回调
        .task {
            await viewModel.preloadModuleSetupCacheIfNeeded()
            await viewModel.loadExistingModuleSettingsIfNeeded()
            await onAppearAction?.call()
        }
    }

    /// 导航栈回退上一页
    private func pop() {
        guard viewModel.navigationPath.isEmpty == false else { return }
        _ = viewModel.navigationPath.popLast()
    }
}
