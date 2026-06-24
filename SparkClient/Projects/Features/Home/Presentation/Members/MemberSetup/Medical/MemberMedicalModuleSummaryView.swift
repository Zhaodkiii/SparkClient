import SwiftUI

/// 医疗模块资料汇总预览页面
/// 展示医疗各小节填写进度，支持一键完整流程、单独编辑小节、完成/暂存退出，关闭弹窗后自动刷新缓存数据
struct MemberMedicalModuleSummaryView: View {
    /// 医疗模块汇总页独立视图模型，管理分区数据、加载、缓存、持久化
    @StateObject private var viewModel: MemberMedicalModuleSummaryViewModel
    /// 持有新建成员总流程ViewModel，用于控制导航栈回退
    @ObservedObject var flowViewModel: MemberSetupFlowViewModel
    /// 自定义回退上层页面回调，无则默认回到模块选择页
    let onPopToParent: (() -> Void)?
    /// 页面退出环境变量
    @Environment(\.dismiss) private var dismiss

    /// 初始化医疗模块汇总页
    /// - Parameters:
    ///   - member: 当前正在创建的家庭成员
    ///   - flowViewModel: 新建成员总流程视图模型
    ///   - onPopToParent: 自定义回退上层页面回调，可选
    init(
        member: Member,
        flowViewModel: MemberSetupFlowViewModel,
        onPopToParent: (() -> Void)? = nil
    ) {
        // 初始化页面独立VM，传入成员与总流程VM
        _viewModel = StateObject(wrappedValue: MemberMedicalModuleSummaryViewModel(member: member, flowViewModel: flowViewModel))
        self.flowViewModel = flowViewModel
        self.onPopToParent = onPopToParent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 模块头部：图标、标题、完成进度、空白提示文案
                MemberModuleSummaryHeaderView(
                    iconName: "heart.fill",
                    iconColor: Color(red: 1.0, green: 0.33, blue: 0.38),
                    title: MemberSetupModule.medical.title,
                    subtitle: viewModel.headerSubtitle,
                    completedCount: viewModel.completedCount,
                    totalCount: viewModel.sections.count,
                    emptyHint: L10n.text("member.setup.medical.general.b74a9a")
                )

                // 一键完整填写医疗全流程入口卡片
                MemberModuleStartAllCard(
                    title: L10n.text("member.setup.medical.general.df476a"),
                    subtitle: L10n.text("member.setup.medical.general.62aaa9")
                ) {
                    viewModel.openFullFlow()
                }

                // 数据加载中占位
                if viewModel.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.text("member.setup.medical.general.a5c25e"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // 加载失败且无任何分区数据，展示重试按钮
                else if let loadError = viewModel.loadError, viewModel.sections.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("member.setup.medical.general.622e7c"))
                            .font(.headline)
                        Text(loadError)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button(L10n.text("common.retry")) {
                            Task { await viewModel.retryLoad() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // 正常渲染各小节卡片列表
                else {
                    // 缓存刷新提示文案
                    if let refreshNotice = viewModel.refreshNotice {
                        Text(refreshNotice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // 遍历医疗所有资料小节，点击进入对应编辑弹窗
                    ForEach(viewModel.sections) { section in
                        MemberModuleSectionCard(section: section) {
                            viewModel.openSection(section)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            // 底部预留操作栏空白，避免内容被遮挡
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(MemberSetupModule.medical.title)
        .navigationBarTitleDisplayMode(.inline)
        // 底部双按钮操作栏：完成持久化 / 暂不填写直接退出
        .memberSetupBottomBar(
            primaryTitle: L10n.text("common.done", fallback: "完成"),
            primaryEnabled: true,
            isLoading: viewModel.isPersisting,
            onPrimary: {
                Task {
                    viewModel.isPersisting = true
                    await viewModel.finishModule()
                    viewModel.isPersisting = false
                    popBack()
                }
            },
            secondaryTitle: L10n.text("member.setup.medical.nutrition.2e16ac"),
            onSecondary: {
                Task {
                    viewModel.isPersisting = true
                    await viewModel.skipModule()
                    viewModel.isPersisting = false
                    popBack()
                }
            }
        )
        // 页面出现自动加载缓存/远程医疗分区数据
        .task {
            await viewModel.loadIfNeeded()
        }
        // 进入页面后延迟自动打开完整流程
        .task {
            try? await Task.sleep(for: .seconds(0.4))
            viewModel.openFullFlow()
        }
        // 模块编辑弹窗关闭后，重新基于本地缓存刷新页面分区列表
        .onChange(of: flowViewModel.activeSheet) { newValue in
            if newValue == nil {
                Task {
                    await viewModel.rebuildSectionsFromCache()
                }
            }
        }
    }

    /// 统一回退逻辑：优先使用外部自定义回调，无则回到模块选择页
    private func popBack() {
        if let onPopToParent {
            onPopToParent()
        } else {
            popToModules()
        }
    }

    /// 导航栈回退至模块选择路由(.modules)
    private func popToModules() {
        if let index = flowViewModel.navigationPath.lastIndex(of: .modules) {
            // 截断导航栈到模块选择页
            flowViewModel.navigationPath = Array(flowViewModel.navigationPath.prefix(index + 1))
        } else {
            // 栈中无模块页则直接重置为仅模块选择页
            flowViewModel.navigationPath = [.modules]
        }
    }
}
