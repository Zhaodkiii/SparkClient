import SwiftUI

/// 新建成员流程-健康功能模块选择页面
/// 展示可开启的医疗/饮食模块开关，支持查看模块详情汇总；底部提供「完成/暂不完善」双操作按钮
struct MemberModuleSetupView: View {
    /// 绑定新建成员流程视图模型，读取模块勾选、完成、加载状态
    @ObservedObject var viewModel: MemberSetupFlowViewModel
    /// 点击模块卡片时打开对应维护 Sheet
    let onOpenModule: (MemberSetupModule) -> Void
    /// 点击底部「完成」按钮执行的回调
    let onDone: () -> Void
    /// 点击底部「暂不完善」按钮执行的回调
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 顶部引导横幅组件
                MemberSetupHeroView(
                    systemImage: "heart.text.square.fill",
                    accentColor: .systemOrange
                )

                // 已创建成员基础信息卡片
                if let member = viewModel.createdMember {
                    MemberSetupStepperCard(
                        title: L10n.text("home.members.field.basic_info", fallback: "基本信息"),
                        systemImage: "person.text.rectangle"
                    ) {
                        memberSummaryRow(member: member)
                    }
                }

                // 模块选择主区域
                VStack(alignment: .leading, spacing: 16) {
                    // 区域标题行
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.title2.weight(.bold))
                            .imageScale(.medium)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                        Text(L10n.text("member.module.selection.title", fallback: "选择维护模块"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                    }

                    // 区域副标题提示文案
                    Text(L10n.text("member.module.selection.subtitle", fallback: "至少开启一个模块，后续可以分步完善"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 16) {
                        // 加载中占位视图
                        if viewModel.isLoadingExistingModules {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(L10n.text("member.module.selection.loading", fallback: "正在读取已开通模块"))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            // 遍历流程可见的健康模块，渲染开关行
                            ForEach(MemberSetupModule.allCases.filter(\.isVisibleInSetup)) { module in
                                MemberModuleToggleRow(
                                    module: module,
                                    selectionStatus: .init(
                                        isSelected: viewModel.selectedModules.contains(module),
                                        isCompleted: viewModel.completedModules.contains(module)
                                    ),
                                    onOpen: {
                                        // 点击模块进入详情汇总预览页
                                         viewModel.openModuleSummary(for: module)
                                        // sheet 打开
//                                        onOpenModule(module)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            // 底部预留底部操作栏空间，避免内容被遮挡
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("member.module.selection.title", fallback: "选择维护模块"))
        .navigationBarTitleDisplayMode(.inline)
        // 隐藏系统返回按钮，统一使用底部操作栏退出流程
        .navigationBarBackButtonHidden(true)
        // 底部双按钮操作栏：完成 / 暂不完善
        .memberSetupBottomBar(
            primaryTitle: L10n.text("common.done", fallback: "完成"),
            primaryEnabled: viewModel.canFinish,
            isLoading: viewModel.isPersistingModules,
            onPrimary: onDone,
            secondaryTitle: L10n.text("member.module.selection.skip", fallback: "暂不完善"),
            onSecondary: onSkip
        )
        // 正在加载模块缓存/读取已有模块时，整页禁用交互
        .disabled(viewModel.isLoadingExistingModules || viewModel.isPreloadingModuleCache)
    }

    /// 成员基础信息行：头像、姓名、亲属关系、模块完成进度角标
    private func memberSummaryRow(member: Member) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(Color(uiColor: .systemBlue))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                    .font(.headline.weight(.semibold))
                Text(MemberRelationshipCatalog.displayTitle(for: member.relationship))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // 全部勾选模块均已填写完成时展示完成角标
            MemberModuleCompletionBadge(
                isCompleted: viewModel.completedModules.filter(\.isVisibleInSetup).count
                    == viewModel.selectedModules.filter(\.isVisibleInSetup).count
                    && viewModel.selectedModules.filter(\.isVisibleInSetup).isEmpty == false
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
