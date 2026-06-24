import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeView: View {
    let dependencies: HomeFeatureDependencies
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator
    @ObservedObject var launchIntentCoordinator: LaunchIntentCoordinator
    let session: UserSession

    private var launchIntentConsumer: HomeLaunchIntentConsumer {
        dependencies.homeLaunchIntentConsumer
    }

    @State private var hasLoaded = false
    @State private var memberActionTarget: Member?
    @State private var activeFullScreenCover: HomeFullScreenCover?
    @State private var addMemberNearbyTransport = NearbyShareTransport()
    @State private var showExternalImportErrorAlert = false

    var body: some View {
        homeContent
    }

    private var homeScrollBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
//                headerCard
                if viewModel.shouldShowMedicalSection {
                    medicalInfoSection
                }
                if viewModel.shouldShowNutritionSection {
                    nutritionInfoSection
                }
                if viewModel.shouldShowModuleMaintenanceSection {
                    moduleMaintenanceSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable {
            await viewModel.refresh()
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            memberSelectorBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial)
        }
    }

    private var homeContentWithPresentation: some View {
        homeScrollBody
            .sheet(item: $viewModel.activeSheet) { sheet in
                homeSheetContent(sheet)
            }
            .fullScreenCover(item: $activeFullScreenCover) { cover in
                homeFullScreenCoverContent(cover)
            }
    }

    private var homeContentWithLifecycle: some View {
        homeContentWithPresentation
            .onAppear {
                launchIntentConsumer.setHomeHostReady(true)
                syncLaunchIntentHostState()
                requestLaunchIntentDrain(reason: "home_appear")
            }
            .onDisappear {
                launchIntentConsumer.setHomeHostReady(false)
            }
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                viewModel.consumePendingShareTicketIfNeeded()
                viewModel.consumePendingInviteIfNeeded()
                await viewModel.loadInitialIfNeeded(syncRemote: true)
                requestLaunchIntentDrain(reason: "home_initial_load")
            }
            .task(id: launchIntentCoordinator.queueRevision) {
                requestLaunchIntentDrain(reason: "queue_revision")
            }
            .onChange(of: launchIntentCoordinator.readiness.canConsume) { canConsume in
                guard canConsume else { return }
                requestLaunchIntentDrain(reason: "readiness_ready")
            }
            .onChange(of: viewModel.activeSheet?.id) { _ in
                syncLaunchIntentHostState()
                requestLaunchIntentDrain(reason: "home_sheet_changed")
            }
            .onReceive(NotificationCenter.default.publisher(for: .medicationReminderPreferencesChanged)) { _ in
                triggerMedicationReminderRebuildIfSignedIn(reason: "preferences_changed")
            }
    }

    private var homeContent: some View {
        homeContentWithLifecycle
            .onChange(of: activeFullScreenCover) { cover in
                if cover != .medicalDocumentUpload, medicalDocumentUploadViewModel.isUploadPresented {
                    medicalDocumentUploadViewModel.dismissUploadPage()
                }
                syncLaunchIntentHostState()
                if cover == nil {
                    requestLaunchIntentDrain(reason: "cover_dismissed")
                }
            }
            .onChange(of: medicalDocumentUploadViewModel.isUploadPresented) { isPresented in
                if isPresented {
                    activeFullScreenCover = .medicalDocumentUpload
                } else if activeFullScreenCover == .medicalDocumentUpload {
                    activeFullScreenCover = nil
                }
                syncLaunchIntentHostState()
                requestLaunchIntentDrain(reason: "upload_presented_changed")
            }
            .onChange(of: medicalDocumentUploadViewModel.stage) { _ in
                syncLaunchIntentHostState()
                requestLaunchIntentDrain(reason: "upload_stage_changed")
            }
            .onChange(of: externalMedicalDocumentImportCoordinator.errorMessage) { message in
                showExternalImportErrorAlert = message != nil
            }
            .alert("无法导入文档", isPresented: $showExternalImportErrorAlert) {
                Button("好", role: .cancel) {
                    externalMedicalDocumentImportCoordinator.clearError()
                }
            } message: {
                Text(externalMedicalDocumentImportCoordinator.errorMessage ?? "")
            }
            .onChange(of: medicalDocumentUploadViewModel.saveSucceededRevision) { _ in
                Task {
                    await viewModel.refresh()
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.selectedMemberID)
    }

    private func syncLaunchIntentHostState() {
        launchIntentConsumer.syncHostState(
            activeSheet: viewModel.activeSheet,
            activeFullScreenCover: activeFullScreenCover,
            isUploadPresented: medicalDocumentUploadViewModel.isUploadPresented,
            uploadStage: medicalDocumentUploadViewModel.stage
        )
    }

    private func requestLaunchIntentDrain(reason: String) {
        launchIntentConsumer.requestDrain(reason: reason) { activeFullScreenCover = $0 }
    }

    private func triggerMedicationReminderRebuildIfSignedIn(reason: String) {
        dependencies.medicationReminderSyncCoordinator.activate(accountID: session.accountID)
        dependencies.medicationReminderSyncCoordinator.requestRebuild(
            accountID: session.accountID,
            members: viewModel.dashboard?.members ?? dependencies.memberContextStore.context.members,
            reason: reason,
            immediate: true
        )
    }

    // MARK: - 首页底部弹窗内容构建器
    /// 弹窗内容统一构造方法，根据弹窗枚举类型渲染对应页面
    /// - Parameter sheet: 首页弹窗类型枚举，区分新增成员/待处理邀请/成员详情等弹窗
    /// - Returns: 对应弹窗的视图内容，部分页面包裹兼容导航容器保证导航栏正常展示
    @ViewBuilder
    private func homeSheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        // MARK: 新增家庭成员弹窗（创建/编辑/接受邀请三种子场景）
        case .addMember(let addMemberSheet):
            // 兼容多版本导航容器，统一弹窗内导航栈样式
            CompatibleNavigationContainer {
                switch addMemberSheet {
                // 场景1：全新创建家庭成员，传入预填单据
                case .create(let pendingTicket):
                    AddFamilyMemberView(
                        mode: .create, // 页面模式：新建成员
                        store: viewModel.memberContextStoreForBinding, // 成员表单状态存储
                        shareUseCase: dependencies.shareMemberUseCase, // 成员分享业务用例
                        inviteUseCase: dependencies.memberInviteUseCase, // 成员邀请业务用例
                        nearbyTransport: addMemberNearbyTransport, // 附近设备互通传输工具
                        initialPendingTicket: pendingTicket, // 初始化预填单据数据
                        // 绑定关系确认完成回调：刷新首页成员列表、拉取待处理邀请
                        onBindingAccepted: {
                            Task {
                                await viewModel.refresh()
                                await viewModel.fetchPendingInvitesIfNeeded()
                            }
                        },
                        // 成员创建成功回调：自动选中当前新建的成员
                        onCreatedMemberCompleted: { member in
                            viewModel.selectMember(member.id)
                        },
                        homeDependencies: dependencies // 首页全局依赖注入
                    )
                // 场景2：编辑已有家庭成员
                case .edit(let member):
                    AddFamilyMemberView(mode: .edit(member), store: viewModel.memberContextStoreForBinding)
                // 场景3：接收他人发来的家庭加入邀请
                case .acceptInvite(let inviteID, let preview):
                    AddFamilyMemberView(
                        mode: .acceptInvite(inviteID: inviteID, preview: preview), // 邀请模式：传入邀请ID与邀请预览信息
                        store: viewModel.memberContextStoreForBinding,
                        inviteUseCase: dependencies.memberInviteUseCase,
                        // 接受邀请完成后刷新首页数据
                        onBindingAccepted: {
                            Task {
                                await viewModel.refresh()
                                await viewModel.fetchPendingInvitesIfNeeded()
                            }
                        }
                    )
                }
            }

        // MARK: 待处理家庭成员邀请列表弹窗
        case .pendingInvites:
            PendingMemberInvitesView(
                items: viewModel.pendingInvites, // 待处理邀请数据源
                highlightInviteID: viewModel.highlightInviteID, // 需要高亮展示的邀请ID
                // 接受邀请：跳转至接受邀请编辑页
                onAccept: { item in
                    viewModel.openInviteAccept(item)
                },
                // 拒绝邀请：主线程异步执行拒绝接口
                onReject: MainActorAsyncAction { item in
                    await viewModel.rejectPendingInvite(item)
                },
                // 页面出现时按需拉取最新邀请列表
                onAppearRefresh: MainActorAsyncVoidAction {
                    await viewModel.fetchPendingInvitesIfNeeded()
                }
            )

        // MARK: 成员功能模块配置流程弹窗
        case .memberModuleSetup(let member):
            MemberSetupFlowView(
                mode: .maintain(member), // 模式：维护已有成员模块配置
                store: viewModel.memberContextStoreForBinding,
                homeDependencies: dependencies,
                // 模块配置/成员创建完成：选中该成员并刷新首页
                onMemberCreated: { member in
                    viewModel.selectMember(member.id)
                    Task { await viewModel.refresh() }
                }
            )

        // MARK: 家庭成员分享弹窗
        case .share(let member):
            ShareSheet(
                member: member, // 需要分享的目标成员
                shareUseCase: dependencies.shareMemberUseCase,
                inviteUseCase: dependencies.memberInviteUseCase
            )

        // MARK: 任务中心弹窗
        case .taskCenter:
            CompatibleNavigationContainer {
                TaskCenterViewController(
                    memberID: viewModel.selectedMemberID, // 当前选中成员ID，用于过滤对应任务
                    taskManager: dependencies.taskManager // 任务管理核心管理器
                )
            }
        }
    }
    // MARK: - 首页全屏弹窗内容构建器
    /// 根据全屏弹窗枚举类型渲染对应全屏页面视图
    /// - Parameter cover: 首页全屏弹窗枚举，区分病历上传、自定义相机等场景
    /// - Returns: 对应场景的全屏视图内容
    @ViewBuilder
    private func homeFullScreenCoverContent(_ cover: HomeFullScreenCover) -> some View {
        switch cover {
        // MARK: 医疗病历/单据上传全屏页
        case .medicalDocumentUpload:
            // 兼容导航容器，提供页面导航栏能力
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(
                    viewModel: medicalDocumentUploadViewModel, // 病历上传页视图模型
                    aiSettingsViewModel: dependencies.aiSettingsViewModel // AI识别配置视图模型
                )
            }

        // MARK: 自定义相机拍摄全屏页
        case .customCamera:
            CustomCameraHomeView {
                // 相机页面关闭回调：清空当前全屏弹窗标识，退出全屏
                activeFullScreenCover = nil
            }

        // MARK: 家庭成员详情全屏页
        case .memberDetail(let memberID):
            memberDetailFullScreenCover(memberID: memberID)
        }
    }

    @ViewBuilder
    private func memberDetailFullScreenCover(memberID: Int) -> some View {
        CompatibleNavigationContainer {
            MemberDetailView(
                memberID: memberID,
                bindingUseCase: dependencies.manageMemberBindingUseCase,
                moduleSetupUseCase: dependencies.memberModuleSetupUseCase,
                nutritionGoalUseCase: dependencies.nutritionDependencies.goalUseCase,
                nutritionDashboardUseCase: dependencies.nutritionDependencies.dashboardUseCase,
                homeDependencies: dependencies,
                memberContextStore: viewModel.memberContextStoreForBinding,
                memberAPI: dependencies.medicalMemberAPI,
                shareUseCase: dependencies.shareMemberUseCase,
                onClose: {
                    activeFullScreenCover = nil
                },
                onShare: {
                    if let member = viewModel.dashboard?.members.first(where: { $0.id == memberID }) {
                        viewModel.activeSheet = .share(member)
                    }
                },
                onEdit: {
                    if let member = viewModel.dashboard?.members.first(where: { $0.id == memberID }) {
                        viewModel.activeSheet = .addMember(.edit(member))
                    }
                },
                onDeleted: {
                    activeFullScreenCover = nil
                    Task { await viewModel.refresh() }
                }
            )
        }
    }
    
    // MARK: - 顶部家庭成员选择栏组件
    /// 左侧待邀请通知按钮 + 横向滚动成员选择标签 + 新增成员按钮
    private var memberSelectorBar: some View {
        HStack(spacing: 8) {
            // 存在未处理邀请时，展示邀请通知铃铛按钮
            if viewModel.pendingInviteCount > 0 {
                Button {
                    // 打开待处理邀请弹窗
                    viewModel.activeSheet = .pendingInvites
                    // 轻触感震动反馈
                    triggerHaptic(style: .light)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        // 铃铛图标
                        Image(systemName: "bell.badge")
                            .font(.title3)
                        // 邀请数量红色角标
                        Text("\(viewModel.pendingInviteCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 8, y: -8)
                    }
                    .frame(width: 40, height: 40)
                }
                // 无障碍文案：待处理邀请数量
                .accessibilityLabel(
                    String(
                        format: L10n.text("home.members.invite.pending_count"),
                        viewModel.pendingInviteCount
                    )
                )
            }
            
            // 横向滚动区域：所有成员选择标签
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // 遍历仪表盘所有家庭成员数据
                    ForEach(viewModel.dashboard?.members ?? []) { member in
                        MemberSelectorChip(
                            member: member, // 当前成员模型
                            badgeText: memberBadgeText(for: member), // 成员附属标签文字（如身份/营养标识）
                            isSelected: member.id == viewModel.selectedMemberID, // 是否为当前选中成员
                            onSelect: {
                                // 选中该成员
                                viewModel.selectMember(member.id)
                                triggerHaptic(style: .light)
                            },
                            onViewDetail: {
                                // 打开成员详情全屏页
                                activeFullScreenCover = .memberDetail(memberID: member.id)
                                triggerHaptic(style: .light)
                            },
                            onShare: {
                                // 打开成员分享弹窗
                                viewModel.activeSheet = .share(member)
                                triggerHaptic(style: .light)
                            }
                        )
                    }
                    
                    // 新增家庭成员圆形加号按钮
                    Button {
                        // 打开新建成员弹窗
                        viewModel.activeSheet = .addMember(.create())
                        // 中等强度震动区分操作
                        triggerHaptic(style: .medium)
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(.quaternary, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    // 无障碍文案：添加家庭成员
                    .accessibilityLabel(L10n.text("home.members.add.title"))
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - 首页头部信息卡片组件
    /// 展示欢迎语、远程模式标识、登录时间，附带任务中心入口按钮
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 欢迎标题行 + 任务中心入口按钮
            HStack(alignment: .top) {
                // 带用户名的欢迎文案
                Text(L10n.homeGreeting(session.displayName))
                    .font(.title.weight(.bold))
                Spacer()
                // 任务中心跳转按钮
                Button {
                    // 打开任务中心全屏弹窗
                    viewModel.activeSheet = .taskCenter
                    // 轻量级触觉反馈
                    triggerHaptic(style: .light)
                } label: {
                    Label(
                        NSLocalizedString("task.center.entry", comment: "任务中心"),
                        systemImage: "checklist"
                    )
                    .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            // 当前运行模式：远程模式提示文本
            Text(L10n.text("home.mode.remote"))
                .font(.callout)
                .foregroundStyle(.secondary)

            // 账号登录时间展示，带认证安全图标
            Label(
                session.signedInAt.formatted(date: .abbreviated, time: .shortened),
                systemImage: "checkmark.seal.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        // 半透明磨砂材质背景
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
        // 细边框描边
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        // 卡片底部柔和阴影，提升悬浮层次感
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    // MARK: - 医疗信息板块组件
    /// 包含医疗板块标题栏、各类医疗数据卡片网格、AI健康报告入口按钮
    private var medicalInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 板块标题行：医疗标题 + 家庭药箱入口 + 当前选中成员名称
            HStack {
                // 医疗板块标题，搭配医疗箱图标
                Label(L10n.text("home.medical.title"), systemImage: "cross.case")
                    .font(.headline)
                Spacer()
                // 存在选中成员时，展示家庭药箱跳转按钮
                if let entryMemberID = viewModel.selectedMemberID {
                    Button {
                        // 路由跳转至对应成员的家庭药箱页面
                        dependencies.routeStore.route(to: .homeFamilyMedicineCabinet(memberID: entryMemberID))
                        // 轻量级触觉反馈
                        triggerHaptic(style: .light)
                    } label: {
                        Label(
                            L10n.text("home.medical.family_cabinet.title"),
                            systemImage: "cross.vial.fill"
                        )
                        .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
                // 展示当前选中家庭成员姓名
//                if viewModel.dashboard?.selectedMember != nil {
//                    Text(viewModel.dashboard?.selectedMember?.name ?? "")
//                        .font(.footnote)
//                        .foregroundStyle(.secondary)
//                }
            }

            // 读取仪表盘医疗模块卡片数组，无数据则为空数组
            let cards = viewModel.dashboard?.medical.cards ?? []
            // 两列自适应网格布局，懒加载优化性能
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(cards, id: \.id) { card in
                    Button {
                        // 埋点：记录医疗分类列表点击日志
                        viewModel.logMedicalListNavigation(kind: card.id)
                        // 路由跳转至对应医疗分类详情列表页
                        dependencies.routeStore.route(to: .homeMedicalList(card.id.homeMedicalListRoute, nil))
                        triggerHaptic(style: .light)
                    } label: {
                        // 渲染单张医疗分类卡片
                        medicalCard(card)
                    }
                    .buttonStyle(.plain)
                }
            }

            // AI健康报告独立入口按钮
            medicalAIReportButton
        }
    }

    private var nutritionInfoSection: some View {
        HomeNutritionEntrySection(
            dependencies: dependencies.nutritionDependencies,
            memberID: viewModel.selectedMemberID
        )
    }

    // MARK: - 健康模块维护板块组件
    /// 用于开通/配置成员医疗、饮食健康模块的入口卡片，无选中成员时置灰不可点击
    private var moduleMaintenanceSection: some View {
        Button {
            // 校验是否存在可配置模块的选中成员，无则直接返回不执行操作
            guard let member = selectedMemberForModuleMaintenance else { return }
            // 打开成员模块配置弹窗
            viewModel.activeSheet = .memberModuleSetup(member)
            // 中等强度触觉反馈，区分普通点击
            triggerHaptic(style: .medium)
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                // 图标 + 标题描述 + 右侧跳转箭头 横向布局
                HStack(alignment: .top, spacing: 14) {
                    // 模块管理网格图标
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.title2.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color(uiColor: .systemTeal))
                        .frame(width: 44, height: 44)
                        // 浅青色圆角背景底色
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: .systemTeal).opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        // 卡片主标题：维护健康模块
                        Text(L10n.text("home.modules.maintenance.title", fallback: "维护健康模块"))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)

                        // 卡片说明副标题，自动换行展示完整提示文案
                        Text(L10n.text("home.modules.maintenance.subtitle", fallback: "当前成员还没有开通医疗或饮食模块，可以从这里维护模块并补充资料。"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    // 右侧右箭头标识，提示可点击跳转
                    Image(systemName: "chevron.forward.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }

                // 底部功能标签组：医疗模块、饮食健康模块标签
                HStack(spacing: 10) {
                    maintenanceModulePill(systemImage: "cross.case.fill", title: L10n.text("member.module.medical.title", fallback: "医疗模块"))
                    maintenanceModulePill(systemImage: "fork.knife.circle.fill", title: L10n.text("member.module.nutrition.title", fallback: "饮食健康"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            // 半透明磨砂材质卡片背景
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
            )
            // 细分割线边框
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
            }
            // 卡片柔和悬浮阴影
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        // 无有效选中成员时，按钮禁用置灰
        .disabled(selectedMemberForModuleMaintenance == nil)
    }

    private func maintenanceModulePill(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }

    private var selectedMemberForModuleMaintenance: Member? {
        if let selectedMember = viewModel.dashboard?.selectedMember {
            return selectedMember
        }
        guard let selectedMemberID = viewModel.selectedMemberID else { return nil }
        return dependencies.memberContextStore.context.members.first(where: { $0.id == selectedMemberID })
    }

    private var customCameraSection: some View {
        HomeCustomCameraEntrySection {
            activeFullScreenCover = .customCamera
        }
    }

    private var medicalAIReportButton: some View {
        Button {
            medicalDocumentUploadViewModel.presentUploadPage()
            triggerHaptic(style: .medium)
        } label: {
            Label(
                L10n.text("home.medical.ai_report", fallback: "AI 智能整理报告"),
                systemImage: "sparkles"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(uiColor: .systemBlue), Color(uiColor: .systemPurple)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(uiColor: .systemBlue).opacity(0.35),
                                Color(uiColor: .systemPurple).opacity(0.35)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedMemberID == nil)
    }

    private func medicalCard(_ card: HomeDashboard.MedicalCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: card.symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemBlue))

            Text(medicalCardTitle(for: card.id))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(medicalCardSubtitle(for: card.id))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Text("\(card.count)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Spacer()
                if let latestDate = card.latestDate {
                    Text(latestDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 1)
        }
    }

    private func memberBadgeText(for member: Member) -> String {
        let display = MemberRelationshipCatalog.displayTitle(for: member.relationship)
        guard let first = display.first else { return "·" }
        return String(first)
    }

    private func medicalCardTitle(for kind: HomeDashboard.MedicalCard.Kind) -> String {
        switch kind {
        case .medicalCases:
            return L10n.text("home.medical.card.medical_cases.title")
        case .healthExamReports:
            return L10n.text("home.medical.card.examination_reports.title")
        case .medicalReports:
            return L10n.text("home.medical.card.medical_reports.title")
        case .medicationPlans:
            return L10n.text("home.medical.card.medication_plans.title")
        }
    }

    private func medicalCardSubtitle(for kind: HomeDashboard.MedicalCard.Kind) -> String {
        switch kind {
        case .medicalCases:
            return L10n.text("home.medical.card.medical_cases.subtitle")
        case .healthExamReports:
            return L10n.text("home.medical.card.examination_reports.subtitle")
        case .medicalReports:
            return L10n.text("home.medical.card.medical_reports.subtitle")
        case .medicationPlans:
            return L10n.text("home.medical.card.medication_plans.subtitle")
        }
    }

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }

    private func triggerNotificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
#if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(type)
#endif
    }
}

/// Member chip with a per-instance action menu (matches Health member button + `confirmationDialog` pattern).
private struct MemberSelectorChip: View {
    let member: Member
    let badgeText: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onViewDetail: () -> Void
    let onShare: () -> Void

    @State private var showActionMenu = false

    var body: some View {
        Button {
            if isSelected {
                showActionMenu = true
            } else {
                onSelect()
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.accentColor.opacity(isSelected ? 0.25 : 0.14))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text(badgeText)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isSelected ? Color.accentColor.opacity(0.95) : .accentColor)
                    }

                Text(member.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))

                if isSelected {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected
                        ? Color.clear
                        : Color(uiColor: .quaternaryLabel).opacity(0.24),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.10 : 0.04), radius: isSelected ? 4 : 2, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .confirmationDialog(L10n.text("home.members.action_title"), isPresented: $showActionMenu, titleVisibility: .visible) {
            Button(L10n.text("home.members.action.view_detail"), systemImage: "person.text.rectangle") {
                onViewDetail()
            }
            if member.effectiveBinding.canShare {
                Button(L10n.text("home.members.action.share"), systemImage: "square.and.arrow.up") {
                    onShare()
                }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        }
    }
}



#if DEBUG
#Preview("Light") {
    CompatibleNavigationContainer {
        HomeView(
            dependencies: .preview,
            viewModel: .preview,
            medicalDocumentUploadViewModel: .preview(),
            externalMedicalDocumentImportCoordinator: AppContainer.preview.externalMedicalDocumentImportCoordinator,
            launchIntentCoordinator: AppContainer.preview.launchIntentCoordinator,
            session: UserSession(
                accountID: 1,
                email: "preview@spark.com",
                displayName: "Spark User",
                signedInAt: .now,
                signInMethod: .apple
            )
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    CompatibleNavigationContainer {
        HomeView(
            dependencies: .preview,
            viewModel: .preview,
            medicalDocumentUploadViewModel: .preview(),
            externalMedicalDocumentImportCoordinator: AppContainer.preview.externalMedicalDocumentImportCoordinator,
            launchIntentCoordinator: AppContainer.preview.launchIntentCoordinator,
            session: UserSession(
                accountID: 1,
                email: "preview@spark.com",
                displayName: "Spark User",
                signedInAt: .now,
                signInMethod: .apple
            )
        )
    }
    .preferredColorScheme(.dark)
}
#endif

#if DEBUG
extension HomeViewModel {
    static var preview: HomeViewModel {
        let now = Date()
        let accountID: Int64 = 1
        let memberA = Member(
            id: 1,
            name: "本人",
            gender: "female",
            relationship: "self",
            birthDate: now.addingTimeInterval(-86_400 * 365 * 30),
            isPrimary: true,
            binding: .ownerLike(bindingID: 1)
        )
        let memberB = Member(
            id: 2,
            name: "妈妈",
            gender: "female",
            relationship: "mother",
            birthDate: now.addingTimeInterval(-86_400 * 365 * 56),
            isPrimary: false,
            binding: .ownerLike(bindingID: 2)
        )

        let previewSession = UserSession(
            accountID: accountID,
            email: "preview@spark.com",
            displayName: "Spark User",
            signedInAt: now,
            signInMethod: .apple
        )

        let dashboard = HomeDashboard(
            session: previewSession,
            members: [memberA, memberB],
            selectedMemberID: memberA.id,
            medical: HomeMedicalOverview(cards: [
                HomeDashboard.MedicalCard(id: .medicalCases, count: 4, latestDate: now.addingTimeInterval(-86_400), symbol: "doc.text.fill"),
                HomeDashboard.MedicalCard(id: .healthExamReports, count: 2, latestDate: now.addingTimeInterval(-172_800), symbol: "heart.text.square.fill"),
                HomeDashboard.MedicalCard(id: .medicalReports, count: 6, latestDate: now.addingTimeInterval(-259_200), symbol: "list.clipboard.fill"),
                HomeDashboard.MedicalCard(id: .medicationPlans, count: 3, latestDate: now.addingTimeInterval(-86_400 * 2), symbol: "calendar.badge.clock")
            ], completeData: nil)
        )

        let sessionStore = AppSessionStore(
            restoreSessionUseCase: RestoreSessionUseCase(authRepository: PreviewAuthRepository())
        )
        sessionStore.setAuthenticated(previewSession)

        let previewPersistence = UserDefaultsSelectedMemberIDStore(
            defaults: UserDefaults(suiteName: "SparkClient.Preview.MemberContext") ?? .standard
        )

        let previewLogger = ConsoleLogger()
        let previewBackend = Backend(baseURL: URL(string: "。.local")!, logger: previewLogger)
        let memberContextStore = MemberContextStore(persistence: previewPersistence)
        memberContextStore.configure(manage: ManageHomeMemberUseCase(memberAPI: previewBackend.medicalMembers))

        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase(
                medicalQueryAPI: SparkMedicalQueryAPI(configuration: previewBackend.configuration),
                selectedMemberIDPersistence: previewPersistence,
                logger: previewLogger
            ),
            loadMembersUseCase: LoadMembersUseCase(
                repository: DefaultMembersRepository(medicalQueryAPI: previewBackend.medicalQuery)
            ),
            memberContextStore: memberContextStore,
            memberModuleSetupUseCase: MemberModuleSetupUseCase(
                medicalQueryAPI: previewBackend.medicalQuery,
                logger: previewLogger
            ),
            shareMemberUseCase: ShareMemberUseCase(memberAPI: previewBackend.medicalMembers),
            memberInviteUseCase: MemberInviteUseCase(memberAPI: previewBackend.medicalMembers),
            manageMemberBindingUseCase: ManageMemberBindingUseCase(memberAPI: previewBackend.medicalMembers),
            notificationClient: PreviewNotificationClient(),
            logger: previewLogger
        )

        viewModel.injectPreviewDashboard(dashboard)
        return viewModel
    }
}

@MainActor
private final class PreviewNotificationClient: NotificationClient {
    func publish(_ intent: NotificationIntent) {}
    func success(_ message: String, title: String?, source: String) {}
    func error(_ message: String, title: String?, source: String) {}
    func warning(_ message: String, title: String?, source: String) {}
    func info(_ message: String, title: String?, source: String) {}
}

private struct PreviewAuthRepository: AuthRepository {
    func restoreSession() async -> UserSession? { nil }

    func signInWithApple(payload: AppleSignInPayload) async throws -> UserSession {
        throw NSError(domain: "PreviewAuthRepository", code: -1)
    }

    func requestPhoneOTP(phoneNumber: String) async throws -> PhoneOTPRequestContext {
        PhoneOTPRequestContext(otpID: "preview-otp-id", expiresIn: 300)
    }

    func signInWithPhoneOTP(phoneNumber: String, verificationCode: String, otpID: String) async throws -> UserSession {
        throw NSError(domain: "PreviewAuthRepository", code: -1)
    }

    func signOut() async throws {}
}
#endif
