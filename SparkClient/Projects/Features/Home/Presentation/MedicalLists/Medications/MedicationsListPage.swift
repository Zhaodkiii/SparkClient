import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum MedicationFilterType: String, Identifiable, CaseIterable {
    case active
    case notStarted
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active:
            return L10n.text("home.medical.list.medications.filter.active", fallback: "执行中")
        case .notStarted:
            return L10n.text("home.medical.list.medications.filter.not_started", fallback: "未开始")
        case .completed:
            return L10n.text("home.medical.list.medications.filter.completed", fallback: "已完成")
        }
    }
}

private enum MedicationListItem: Identifiable {
    case prescription(id: Int, prescription: SparkMedicalSyncAPI.RemotePrescription?, plans: [SparkMedicalSyncAPI.RemoteMedicationPlan])
    case standalonePlan(SparkMedicalSyncAPI.RemoteMedicationPlan)

    var id: String {
        switch self {
        case .prescription(let id, _, _):
            return "prescription_\(id)"
        case .standalonePlan(let plan):
            return "plan_\(plan.id)"
        }
    }

    var sortDate: Date {
        switch self {
        case .prescription(_, let prescription, let plans):
            return prescription?.prescribedAt
                ?? plans.map(\.startDate).max()
                ?? prescription?.updatedAt
                ?? .distantPast
        case .standalonePlan(let plan):
            return plan.startDate
        }
    }
}

/// 服药计划/处方/药箱统一列表页面（个人药箱首页）
struct MedicationsListPage: View {
    /// 完整同步后的成员医疗全量数据（后端同步模型）
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    /// 医疗工作流接口服务
    let workflowAPI: SparkMedicalWorkflowAPI
    /// 医疗数据查询接口服务
    let medicalQueryAPI: SparkMedicalQueryAPI
    /// 文件传输/上传服务
    let fileTransferService: FileTransferService
    /// 成员上下文状态管理对象（当前选中家庭成员）
    @ObservedObject var memberContextStore: MemberContextStore
    /// 医疗单据上传页面视图模型（处方/服药单OCR识别）
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    /// AI配置视图模型（OCR识别、AI解读参数）
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    /// 系统通知弹窗客户端（成功/失败提示）
    let notificationClient: any NotificationClient
    /// 日志打印工具类
    let logger: Logger
    /// 首页Feature层全局依赖容器（个人药箱专用）
    let homeDependencies: HomeFeatureDependencies?
    /// 服药计划数据变更回调
    let onMedicationPlansChanged: (([SparkMedicalSyncAPI.RemoteMedicationPlan]) -> Void)?
    /// 处方列表数据变更回调
    let onPrescriptionsChanged: (([SparkMedicalSyncAPI.RemotePrescription]) -> Void)?
    /// 药箱药品数据变更回调
    let onMedicineBoxesChanged: (([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void)?

    // MARK: - 页面状态变量
    /// 当前选中筛选标签：进行中/未开始/已完成
    @State private var selectedFilter: MedicationFilterType = .active
    /// 本地缓存药箱药品数组
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    /// 本地缓存处方数组
    @State private var prescriptions: [SparkMedicalSyncAPI.RemotePrescription]
    /// 本地缓存服药计划数组
    @State private var medicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    /// 今日服药打卡记录
    @State private var todayMedicationRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    /// 弹窗路由目标（新增/编辑服药计划表单）
    @State private var sheetDestination: MedicationPlanSheetDestination?
    /// 是否展示服药通知权限申请弹窗
    @State private var showMedicationReminderPermissionExplanation = false

    /// 日志模块标记：首页模块
    private let logModule = LogModule.home

    // MARK: - 构造方法
    init(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        workflowAPI: SparkMedicalWorkflowAPI,
        medicalQueryAPI: SparkMedicalQueryAPI,
        fileTransferService: FileTransferService,
        memberContextStore: MemberContextStore,
        medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel,
        aiSettingsViewModel: AISettingsViewModel,
        notificationClient: any NotificationClient,
        logger: Logger,
        homeDependencies: HomeFeatureDependencies? = nil,
        onMedicationPlansChanged: (([SparkMedicalSyncAPI.RemoteMedicationPlan]) -> Void)? = nil,
        onPrescriptionsChanged: (([SparkMedicalSyncAPI.RemotePrescription]) -> Void)? = nil,
        onMedicineBoxesChanged: (([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void)? = nil
    ) {
        // 注入外部依赖
        self.completeData = completeData
        self.workflowAPI = workflowAPI
        self.medicalQueryAPI = medicalQueryAPI
        self.fileTransferService = fileTransferService
        self.memberContextStore = memberContextStore
        self.medicalDocumentUploadViewModel = medicalDocumentUploadViewModel
        self.aiSettingsViewModel = aiSettingsViewModel
        self.notificationClient = notificationClient
        self.logger = logger
        self.homeDependencies = homeDependencies
        self.onMedicationPlansChanged = onMedicationPlansChanged
        self.onPrescriptionsChanged = onPrescriptionsChanged
        self.onMedicineBoxesChanged = onMedicineBoxesChanged
        
        // 从同步数据初始化本地State缓存，无数据则为空数组
        _medicineBoxes = State(initialValue: completeData?.medicineBoxes ?? [])
        _prescriptions = State(initialValue: completeData?.prescriptions ?? [])
        _medicationPlans = State(initialValue: completeData?.medicationPlans ?? [])
        _todayMedicationRecords = State(initialValue: completeData?.todayMedicationRecords ?? [])
    }

    // MARK: - 计算属性：基础数据映射
    /// 当前操作成员ID：优先取同步数据，无则取上下文选中成员ID
    private var memberID: Int? {
        completeData?.memberId ?? memberContextStore.context.selectedMember?.id
    }

    /// 药箱字典：key=药品ID，value=药品模型（快速索引）
    private var medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox] {
        Dictionary(uniqueKeysWithValues: medicineBoxes.map { ($0.id, $0) })
    }

    /// 服药记录分组字典：key=服药计划ID，value=该计划今日打卡记录数组
    private var recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]] {
        Dictionary(grouping: todayMedicationRecords, by: \.plan)
    }

    /// 处方字典：key=处方ID，value=处方模型（快速索引）
    private var prescriptionsByID: [Int: SparkMedicalSyncAPI.RemotePrescription] {
        Dictionary(uniqueKeysWithValues: prescriptions.map { ($0.id, $0) })
    }

    /// 排序后的服药计划列表：按状态优先级 + 创建时间倒序
    private var sortedPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan] {
        medicationPlans.sorted { lhs, rhs in
            // 状态相同则按开始时间从新到旧
            if lhs.status == rhs.status {
                return lhs.startDate > rhs.startDate
            }
            // 按状态权重排序（进行中优先展示）
            return statusRank(lhs.status) < statusRank(rhs.status)
        }
    }

    // MARK: - 计算属性：页面渲染数据源
    /// 组装页面统一渲染Item模型（处方关联计划 / 独立无处方计划）
    private var sortedItems: [MedicationListItem] {
        // 筛选绑定了处方的服药计划
        let linkedPlans = sortedPlans.filter { $0.prescription != nil }
        // 按处方ID分组计划
        let plansByPrescriptionID = Dictionary(grouping: linkedPlans) { plan in
            plan.prescription ?? 0
        }

        var items: [MedicationListItem] = []
        // 合并所有处方ID集合（已有处方 + 计划关联处方）
        let prescriptionIDs = Set(prescriptions.map(\.id)).union(plansByPrescriptionID.keys)
        
        // 组装【处方+关联服药计划】类型Item
        for prescriptionID in prescriptionIDs {
            let plans = plansByPrescriptionID[prescriptionID] ?? []
            if prescriptionsByID[prescriptionID] != nil || !plans.isEmpty {
                items.append(.prescription(id: prescriptionID, prescription: prescriptionsByID[prescriptionID], plans: plans))
            }
        }

        // 组装【独立无处方服药计划】类型Item
        for plan in sortedPlans where plan.prescription == nil {
            items.append(.standalonePlan(plan))
        }

        // 统一按业务排序字段倒序
        return items.sorted { $0.sortDate > $1.sortDate }
    }

    /// 根据顶部筛选标签过滤展示列表数据
    private var filteredItems: [MedicationListItem] {
        sortedItems.filter { item in
            switch selectedFilter {
            case .active:
                // 进行中：存在状态active且在有效日期区间的计划
                return item.plans.contains { $0.status == "active" && isPlanInDateRange($0) }
            case .notStarted:
                // 未开始：暂停中 / 开始日期晚于今日
                return item.plans.contains { $0.status == "paused" || $0.startDate > today }
            case .completed:
                // 已完成：所有计划均为完成/取消/已过结束日期
                return !item.plans.isEmpty && item.plans.allSatisfy {
                    $0.status == "completed" || $0.status == "cancelled" || isPlanEnded($0)
                }
            }
        }
    }

    /// 获取今日零点日期对象
    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    // MARK: - 页面主体结构
    var body: some View {
        contentWithLifecycle
            // 新增/编辑服药计划弹窗
            .sheet(item: $sheetDestination) { destination in
                medicationPlanSheetContent(for: destination)
            }
            // 处方OCR上传全屏页面
            .fullScreenCover(isPresented: $medicalDocumentUploadViewModel.isUploadPresented) {
                uploadHostView
            }
            // 服药通知权限申请弹窗组件
            .medicationReminderPermissionExplanation(
                isPresented: $showMedicationReminderPermissionExplanation,
                onContinue: { confirmMedicationReminderPermissionRequest() },
                onSkip: { skipMedicationReminderPermissionRequest() }
            )
    }

    /// 页面生命周期监听容器（出现、数据变更回调）
    private var contentWithLifecycle: some View {
        contentChrome
            .onAppear(perform: logAppear)
            // 筛选标签切换监听
            .onChange(of: selectedFilter, perform: handleFilterChange)
            // 外部同步数据变更监听，同步至本地State
            .onChange(of: completeData?.medicineBoxes ?? [], perform: handleMedicineBoxesChange)
            .onChange(of: completeData?.prescriptions ?? [], perform: handlePrescriptionsChange)
            .onChange(of: completeData?.medicationPlans ?? [], perform: handleMedicationPlansChange)
            .onChange(of: completeData?.todayMedicationRecords ?? [], perform: handleMedicationRecordsChange)
            // OCR单据保存成功后刷新列表
            .onChange(of: medicalDocumentUploadViewModel.saveSucceededRevision) { _ in
                Task { await refreshAfterMedicalUploadSave() }
            }
    }

    /// 页面外层容器（导航栏、底部操作栏、背景）
    private var contentChrome: some View {
        contentRoot
            // 底部固定操作栏：手动新增、拍照上传识别处方
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MedicalListBottomActionBar(
                    documentType: .medicationPlan,
                    isEnabled: memberID != nil,
                    onManualAdd: { sheetDestination = .create },
                    onUploadConfirmed: { files in startMedicationPlanRecognition(files: files) }
                )
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L10n.text("home.medical.list.medications.title", fallback: "服药计划"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let homeDependencies {
                        MainNavigationLink {
                            MedicationReminderManagementPage(homeDependencies: homeDependencies)
                        } label: {
                            Label(
                                L10n.text("medication_reminder.management.title", fallback: "已有通知"),
                                systemImage: "bell.badge"
                            )
                            .font(.footnote.weight(.semibold))
                        }
                    }
                }                
//                // 服药执行中心入口
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    AnyView(executionCenterToolbarLink)
//                }
//                // 个人药箱入口
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    AnyView(medicineBoxToolbarLink)
//                }
            }
    }

    /// 页面根布局：筛选标签 + 滚动列表区域
    private var contentRoot: some View {
        VStack(spacing: 0) {
            filterTabBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            medicationScrollableContent
        }
    }

    // MARK: - 生命周期/数据变更处理函数
    /// 页面出现埋点日志
    private func logAppear() {
        logger.info(
            "打开服药计划列表 filter=\(selectedFilter.rawValue) total=\(sortedItems.count) filtered=\(filteredItems.count)",
            module: logModule
        )
    }

    /// 切换筛选标签埋点日志
    private func handleFilterChange(_ newValue: MedicationFilterType) {
        logger.info(
            "切换服药计划筛选 filter=\(newValue.rawValue) filtered=\(filteredItems.count)",
            module: logModule
        )
    }

    /// 外部药箱数据同步更新本地缓存
    private func handleMedicineBoxesChange(_ newValue: [SparkMedicalSyncAPI.RemoteMedicineBox]) {
        medicineBoxes = newValue
    }

    /// 外部处方数据同步更新本地缓存
    private func handlePrescriptionsChange(_ newValue: [SparkMedicalSyncAPI.RemotePrescription]) {
        prescriptions = newValue
    }

    /// 外部服药计划数据同步更新本地缓存
    private func handleMedicationPlansChange(_ newValue: [SparkMedicalSyncAPI.RemoteMedicationPlan]) {
        medicationPlans = newValue
    }

    /// 外部今日打卡记录同步更新本地缓存
    private func handleMedicationRecordsChange(_ newValue: [SparkMedicalSyncAPI.RemoteMedicationRecord]) {
        todayMedicationRecords = newValue
    }

    // MARK: - 弹窗页面构造
    /// 服药计划新增/编辑表单弹窗内容
    @ViewBuilder
    private func medicationPlanSheetContent(for destination: MedicationPlanSheetDestination) -> some View {
        if let memberID {
            MedicationPlanFormView(
                mode: destination.formMode,
                memberID: memberID,
                medicineBoxes: medicineBoxes,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                notificationClient: notificationClient,
                onMedicineBoxSaved: upsertMedicineBox,
                onServerSaved: upsertMedicationPlan
            )
        } else {
            // 未选择成员提示文案
            Text(L10n.text("home.medical.list.medications.select_member_first", fallback: "请先选择成员"))
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 处方OCR上传全屏页面容器
    private var uploadHostView: some View {
        CompatibleNavigationContainer {
            MedicalDocumentUploadHostView(
                viewModel: medicalDocumentUploadViewModel,
                aiSettingsViewModel: aiSettingsViewModel
            )
        }
    }

    // MARK: - 导航栏工具栏入口
    /// 服药执行中心快捷入口
    private var executionCenterToolbarLink: some View {
        MainNavigationLink {
            MedicationExecutionCenterPage(
                medicationPlans: medicationPlans,
                medicineBoxes: medicineBoxes,
                initialRecords: todayMedicationRecords,
                memberID: memberID,
                medicalQueryAPI: medicalQueryAPI,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                notificationClient: notificationClient,
                logger: logger,
                completeData: completeData,
                memberContextStore: memberContextStore,
                medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                onMedicationPlansChanged: onMedicationPlansChanged,
                onPrescriptionsChanged: onPrescriptionsChanged,
                onMedicineBoxesChanged: updateMedicineBoxes
            )
        } label: {
            Label(L10n.text("home.medical.list.medications.action.execution_center", fallback: "执行"), systemImage: "checklist.checked")
                .font(.footnote.weight(.semibold))
        }
        .disabled(memberID == nil)
    }

    /// 个人药箱工具栏入口（单人模式药箱页面）
    @ViewBuilder
    private var medicineBoxToolbarLink: some View {
        // 个人药箱入口：复用 FamilyMedicineCabinetPage 的 personal 模式
        if let memberID, let homeDependencies {
            MainNavigationLink {
                FamilyMedicineCabinetPage(
                    entryMemberID: memberID,
                    mode: .personal,
                    initialMedicineBoxes: medicineBoxes,
                    dependencies: homeDependencies,
                    onMedicineBoxesChanged: updateMedicineBoxes
                )
            } label: {
                Label(L10n.text("home.medical.list.medications.action.medicine_box", fallback: "药箱"), systemImage: "pills.fill")
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    // MARK: - 筛选标签栏组件
    private var filterTabBar: some View {
        HStack(spacing: 0) {
            ForEach(MedicationFilterType.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    VStack(spacing: 8) {
                        Text(filter.title)
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

    // MARK: - 列表滚动区域
    private var medicationScrollableContent: some View {
        ScrollView {
            if filteredItems.isEmpty {
                // 无数据空白页
                emptyStateView
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems) { item in
                        switch item {
                        case .prescription(_, let prescription, let plans):
                            // 处方卡片跳转处方详情页
                            MainNavigationLink {
                                MedicationPrescriptionDetailPage(
                                    prescription: prescription,
                                    plans: plans,
                                    medicineBoxes: medicineBoxes,
                                    recordsByPlanID: recordsByPlanID,
                                    memberID: memberID,
                                    completeData: completeData,
                                    memberContextStore: memberContextStore,
                                    workflowAPI: workflowAPI,
                                    fileTransferService: fileTransferService,
                                    notificationClient: notificationClient,
                                    onPrescriptionSaved: upsertPrescription,
                                    onPrescriptionDeleted: removePrescription,
                                    onPlanSaved: upsertMedicationPlan,
                                    onPlanDeleted: removeMedicationPlan
                                )
                            } label: {
                                MedicationPrescriptionCard(
                                    prescription: prescription,
                                    plans: plans,
                                    medicineBoxesByID: medicineBoxesByID,
                                    recordsByPlanID: recordsByPlanID,
                                    fileTransferService: fileTransferService,
                                    planDestination: planDetailPage
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        case .standalonePlan(let plan):
                            // 独立服药计划卡片跳转计划详情
                            MainNavigationLink {
                                planDetailPage(for: plan)
                            } label: {
                                MedicationPlanCard(
                                    plan: plan,
                                    medicineBox: plan.medicineBox.flatMap { medicineBoxesByID[$0] },
                                    records: recordsByPlanID[plan.id] ?? [],
                                    fileTransferService: fileTransferService
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }

                    Text(L10n.text("home.medical.list.medications.footer.no_more", fallback: "没有更多了"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.bottom, 96)
                }
            }
        }
        .refreshable {
            // 下拉刷新列表数据
            await refreshMedicationPlans()
        }
    }

    /// 服药计划详情页面构造
    private func planDetailPage(for plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> some View {
        MedicationPlanDetailPage(
            plan: plan,
            medicineBoxes: medicineBoxes,
            records: recordsByPlanID[plan.id] ?? [],
            memberID: memberID,
            completeData: completeData,
            memberContextStore: memberContextStore,
            workflowAPI: workflowAPI,
            fileTransferService: fileTransferService,
            notificationClient: notificationClient,
            onSaved: upsertMedicationPlan,
            onDeleted: removeMedicationPlan,
            onMedicineBoxSaved: upsertMedicineBox,
            onMedicineBoxDeleted: removeMedicineBoxFromList
        )
    }

    /// 列表空白占位页面
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(L10n.text("home.medical.list.medications.empty.title", fallback: "暂无服药计划"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(L10n.text("home.medical.list.medications.empty.subtitle", fallback: "创建服药计划后，可按时间、剂量和频次跟踪。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - 本地数据增删改方法（更新State并回调外部）
    /// 新增/编辑服药计划，更新本地列表并触发外部回调
    private func upsertMedicationPlan(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) {
        if let index = medicationPlans.firstIndex(where: { $0.id == plan.id }) {
            medicationPlans[index] = plan
        } else {
            medicationPlans.insert(plan, at: 0)
        }
        onMedicationPlansChanged?(medicationPlans)
        notifyMedicationPlanChanged(plan)
        sheetDestination = nil
    }

    /// 删除指定ID服药计划
    private func removeMedicationPlan(id: Int) {
        medicationPlans.removeAll { $0.id == id }
        onMedicationPlansChanged?(medicationPlans)
        notifyMedicationPlanChanged(nil)
    }

    /// 服药计划变更后同步刷新本地通知提醒
    private func notifyMedicationPlanChanged(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan?) {
        guard let homeDependencies else { return }
        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }

        let members = memberContextStore.context.members
        let coordinator = homeDependencies.medicationReminderSyncCoordinator
        coordinator.activate(accountID: session.accountID)

        // 当前计划未开启提醒，直接重建提醒数据
        guard plan?.reminderEnabled == true else {
            coordinator.rebuildAfterPlanChanged(accountID: session.accountID, members: members)
            return
        }

        Task {
            let status = await coordinator.permissionCoordinatorAccess.currentStatus()
            // 未申请通知权限，弹出权限引导弹窗
            if status == .notDetermined {
                showMedicationReminderPermissionExplanation = true
                return
            }
            coordinator.rebuildAfterPlanChanged(accountID: session.accountID, members: members)
        }
    }

    /// 用户确认申请系统通知权限
    private func confirmMedicationReminderPermissionRequest() {
        guard let homeDependencies else { return }
        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
        Task {
            await homeDependencies.medicationReminderSyncCoordinator.requestSystemPermissionAndRebuild(
                accountID: session.accountID,
                members: memberContextStore.context.members
            )
        }
    }

    /// 用户跳过权限申请，直接生成提醒
    private func skipMedicationReminderPermissionRequest() {
        guard let homeDependencies else { return }
        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
        notificationClient.info(
            L10n.text("medication_reminder.permission.skipped_toast"),
            title: L10n.text("medication_reminder.title"),
            source: "medication_reminder"
        )
        homeDependencies.medicationReminderSyncCoordinator.rebuildAfterPlanChanged(
            accountID: session.accountID,
            members: memberContextStore.context.members
        )
    }

    /// 新增/编辑处方
    private func upsertPrescription(_ prescription: SparkMedicalSyncAPI.RemotePrescription) {
        if let index = prescriptions.firstIndex(where: { $0.id == prescription.id }) {
            prescriptions[index] = prescription
        } else {
            prescriptions.insert(prescription, at: 0)
        }
        onPrescriptionsChanged?(prescriptions)
    }

    /// 删除指定ID处方
    private func removePrescription(id: Int) {
        prescriptions.removeAll { $0.id == id }
        onPrescriptionsChanged?(prescriptions)
    }

    /// 新增/编辑药箱药品
    private func upsertMedicineBox(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
            medicineBoxes[index] = box
        } else {
            medicineBoxes.insert(box, at: 0)
        }
        onMedicineBoxesChanged?(medicineBoxes)
    }

    /// 从本地列表删除指定药品
    private func removeMedicineBoxFromList(_ id: Int) {
        medicineBoxes.removeAll { $0.id == id }
        onMedicineBoxesChanged?(medicineBoxes)
    }

    /// 批量替换全量药箱数据
    private func updateMedicineBoxes(_ boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]) {
        medicineBoxes = boxes
        onMedicineBoxesChanged?(boxes)
    }

    // MARK: - 网络刷新接口
    /// 下拉刷新：拉取服药计划、处方列表
    @MainActor
    private func refreshMedicationPlans() async {
        guard let memberID else {
            logger.warning("服药计划下拉刷新跳过：缺少成员 ID", module: logModule)
            return
        }

        let startedAt = Date()
        logger.info("服药计划下拉刷新开始 memberID=\(memberID)", module: logModule)

        do {
            // 并发请求两个接口
            async let refreshedPlans = medicalQueryAPI.listMedicationPlans(memberID: memberID)
            async let refreshedPrescriptions = medicalQueryAPI.listPrescriptions(memberID: memberID)
            let (plans, prescriptionRows) = try await (refreshedPlans, refreshedPrescriptions)
            // 更新本地缓存并回调外部
            medicationPlans = plans
            prescriptions = prescriptionRows
            onMedicationPlansChanged?(plans)
            onPrescriptionsChanged?(prescriptionRows)
            logger.info(
                "服药计划下拉刷新完成 memberID=\(memberID) plans=\(plans.count) prescriptions=\(prescriptionRows.count) cost=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s",
                module: logModule
            )
        } catch {
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.medication_plans.refresh")
            logger.warning("服药计划下拉刷新失败 memberID=\(memberID) error=\(error.localizedDescription)", module: logModule)
        }
    }

    /// OCR单据保存完成后刷新计划+药箱数据
    @MainActor
    private func refreshAfterMedicalUploadSave() async {
        await refreshMedicationPlans()
        guard let memberID else { return }
        do {
            let boxes = try await medicalQueryAPI.listMedicineBoxes(memberID: memberID)
            medicineBoxes = boxes
            onMedicineBoxesChanged?(boxes)
        } catch {
            logger.warning("AI 保存后刷新药箱失败 memberID=\(memberID) error=\(error.localizedDescription)", module: logModule)
        }
    }

    /// 启动处方图片OCR识别流程
    @MainActor
    private func startMedicationPlanRecognition(files: [MedicalUploadLocalFile]) {
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .medicationPlan)
    }

    // MARK: - 状态/日期工具函数
    /// 服药计划状态权重排序规则：数字越小优先级越高
    private func statusRank(_ status: String) -> Int {
        switch status {
        case "active":
            return 0
        case "paused":
            return 1
        case "completed":
            return 2
        case "cancelled":
            return 3
        default:
            return 4
        }
    }

    /// 判断计划是否在有效日期区间（已开始且未结束）
    private func isPlanInDateRange(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> Bool {
        plan.startDate <= today && !isPlanEnded(plan)
    }

    /// 判断计划是否已过期（存在结束日期且早于今日）
    private func isPlanEnded(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> Bool {
        guard let endDate = plan.endDate else {
            return false
        }
        return endDate < today
    }
}

//struct MedicationsListPage: View {
//    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
//    let workflowAPI: SparkMedicalWorkflowAPI
//    let medicalQueryAPI: SparkMedicalQueryAPI
//    let fileTransferService: FileTransferService
//    @ObservedObject var memberContextStore: MemberContextStore
//    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
//    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
//    let notificationClient: any NotificationClient
//    let logger: Logger
//    /// 个人药箱入口所需的完整 Home 依赖
//    let homeDependencies: HomeFeatureDependencies?
//    let onMedicationPlansChanged: (([SparkMedicalSyncAPI.RemoteMedicationPlan]) -> Void)?
//    let onPrescriptionsChanged: (([SparkMedicalSyncAPI.RemotePrescription]) -> Void)?
//    let onMedicineBoxesChanged: (([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void)?
//
//    @State private var selectedFilter: MedicationFilterType = .active
//    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
//    @State private var prescriptions: [SparkMedicalSyncAPI.RemotePrescription]
//    @State private var medicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
//    @State private var todayMedicationRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord]
//    @State private var sheetDestination: MedicationPlanSheetDestination?
//    @State private var showMedicationReminderPermissionExplanation = false
//
//    private let logModule = LogModule.home
//
//    init(
//        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
//        workflowAPI: SparkMedicalWorkflowAPI,
//        medicalQueryAPI: SparkMedicalQueryAPI,
//        fileTransferService: FileTransferService,
//        memberContextStore: MemberContextStore,
//        medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel,
//        aiSettingsViewModel: AISettingsViewModel,
//        notificationClient: any NotificationClient,
//        logger: Logger,
//        homeDependencies: HomeFeatureDependencies? = nil,
//        onMedicationPlansChanged: (([SparkMedicalSyncAPI.RemoteMedicationPlan]) -> Void)? = nil,
//        onPrescriptionsChanged: (([SparkMedicalSyncAPI.RemotePrescription]) -> Void)? = nil,
//        onMedicineBoxesChanged: (([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void)? = nil
//    ) {
//        self.completeData = completeData
//        self.workflowAPI = workflowAPI
//        self.medicalQueryAPI = medicalQueryAPI
//        self.fileTransferService = fileTransferService
//        self.memberContextStore = memberContextStore
//        self.medicalDocumentUploadViewModel = medicalDocumentUploadViewModel
//        self.aiSettingsViewModel = aiSettingsViewModel
//        self.notificationClient = notificationClient
//        self.logger = logger
//        self.homeDependencies = homeDependencies
//        self.onMedicationPlansChanged = onMedicationPlansChanged
//        self.onPrescriptionsChanged = onPrescriptionsChanged
//        self.onMedicineBoxesChanged = onMedicineBoxesChanged
//        _medicineBoxes = State(initialValue: completeData?.medicineBoxes ?? [])
//        _prescriptions = State(initialValue: completeData?.prescriptions ?? [])
//        _medicationPlans = State(initialValue: completeData?.medicationPlans ?? [])
//        _todayMedicationRecords = State(initialValue: completeData?.todayMedicationRecords ?? [])
//    }
//
//    private var memberID: Int? {
//        completeData?.memberId ?? memberContextStore.context.selectedMember?.id
//    }
//
//    private var medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox] {
//        Dictionary(uniqueKeysWithValues: medicineBoxes.map { ($0.id, $0) })
//    }
//
//    private var recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]] {
//        Dictionary(grouping: todayMedicationRecords, by: \.plan)
//    }
//
//    private var prescriptionsByID: [Int: SparkMedicalSyncAPI.RemotePrescription] {
//        Dictionary(uniqueKeysWithValues: prescriptions.map { ($0.id, $0) })
//    }
//
//    private var sortedPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan] {
//        medicationPlans.sorted { lhs, rhs in
//            if lhs.status == rhs.status {
//                return lhs.startDate > rhs.startDate
//            }
//            return statusRank(lhs.status) < statusRank(rhs.status)
//        }
//    }
//
//    private var sortedItems: [MedicationListItem] {
//        let linkedPlans = sortedPlans.filter { $0.prescription != nil }
//        let plansByPrescriptionID = Dictionary(grouping: linkedPlans) { plan in
//            plan.prescription ?? 0
//        }
//
//        var items: [MedicationListItem] = []
//        let prescriptionIDs = Set(prescriptions.map(\.id)).union(plansByPrescriptionID.keys)
//        for prescriptionID in prescriptionIDs {
//            let plans = plansByPrescriptionID[prescriptionID] ?? []
//            if prescriptionsByID[prescriptionID] != nil || plans.isEmpty == false {
//                items.append(.prescription(id: prescriptionID, prescription: prescriptionsByID[prescriptionID], plans: plans))
//            }
//        }
//
//        for plan in sortedPlans where plan.prescription == nil {
//            items.append(.standalonePlan(plan))
//        }
//
//        return items.sorted { $0.sortDate > $1.sortDate }
//    }
//
//    private var filteredItems: [MedicationListItem] {
//        sortedItems.filter { item in
//            switch selectedFilter {
//            case .active:
//                return item.plans.contains { $0.status == "active" && isPlanInDateRange($0) }
//            case .notStarted:
//                return item.plans.contains { $0.status == "paused" || $0.startDate > today }
//            case .completed:
//                return item.plans.isEmpty == false && item.plans.allSatisfy {
//                    $0.status == "completed" || $0.status == "cancelled" || isPlanEnded($0)
//                }
//            }
//        }
//    }
//
//    private var today: Date {
//        Calendar.current.startOfDay(for: Date())
//    }
//
//    var body: some View {
//        contentWithLifecycle
//            .sheet(item: $sheetDestination) { destination in
//                medicationPlanSheetContent(for: destination)
//            }
//            .fullScreenCover(isPresented: $medicalDocumentUploadViewModel.isUploadPresented) {
//                uploadHostView
//            }
//            .medicationReminderPermissionExplanation(
//                isPresented: $showMedicationReminderPermissionExplanation,
//                onContinue: { confirmMedicationReminderPermissionRequest() },
//                onSkip: { skipMedicationReminderPermissionRequest() }
//            )
//    }
//
//    private var contentWithLifecycle: some View {
//        contentChrome
//            .onAppear(perform: logAppear)
//            .onChange(of: selectedFilter, perform: handleFilterChange)
//            .onChange(of: completeData?.medicineBoxes ?? [], perform: handleMedicineBoxesChange)
//            .onChange(of: completeData?.prescriptions ?? [], perform: handlePrescriptionsChange)
//            .onChange(of: completeData?.medicationPlans ?? [], perform: handleMedicationPlansChange)
//            .onChange(of: completeData?.todayMedicationRecords ?? [], perform: handleMedicationRecordsChange)
//            .onChange(of: medicalDocumentUploadViewModel.saveSucceededRevision) { _ in
//                Task { await refreshAfterMedicalUploadSave() }
//            }
//    }
//
//    private var contentChrome: some View {
//        contentRoot
//            .safeAreaInset(edge: .bottom, spacing: 0) {
//                MedicalListBottomActionBar(
//                    documentType: .medicationPlan,
//                    isEnabled: memberID != nil,
//                    onManualAdd: { sheetDestination = .create },
//                    onUploadConfirmed: { files in startMedicationPlanRecognition(files: files) }
//                )
//            }
//            .background(Color(uiColor: .systemGroupedBackground))
//            .navigationTitle(L10n.text("home.medical.list.medications.title", fallback: "服药计划"))
//            .navigationBarTitleDisplayMode(.inline)
////            .toolbar {
////                ToolbarItem(placement: .navigationBarTrailing) {
////                    AnyView(executionCenterToolbarLink)
////                }
////                ToolbarItem(placement: .navigationBarTrailing) {
////                    AnyView(medicineBoxToolbarLink)
////                }
////            }
//    }
//
//    private var contentRoot: some View {
//        VStack(spacing: 0) {
//            filterTabBar
//                .padding(.horizontal, 16)
//                .padding(.vertical, 12)
//
//            medicationScrollableContent
//        }
//    }
//
//    private func logAppear() {
//        logger.info(
//            "打开服药计划列表 filter=\(selectedFilter.rawValue) total=\(sortedItems.count) filtered=\(filteredItems.count)",
//            module: logModule
//        )
//    }
//
//    private func handleFilterChange(_ newValue: MedicationFilterType) {
//        logger.info(
//            "切换服药计划筛选 filter=\(newValue.rawValue) filtered=\(filteredItems.count)",
//            module: logModule
//        )
//    }
//
//    private func handleMedicineBoxesChange(_ newValue: [SparkMedicalSyncAPI.RemoteMedicineBox]) {
//        medicineBoxes = newValue
//    }
//
//    private func handlePrescriptionsChange(_ newValue: [SparkMedicalSyncAPI.RemotePrescription]) {
//        prescriptions = newValue
//    }
//
//    private func handleMedicationPlansChange(_ newValue: [SparkMedicalSyncAPI.RemoteMedicationPlan]) {
//        medicationPlans = newValue
//    }
//
//    private func handleMedicationRecordsChange(_ newValue: [SparkMedicalSyncAPI.RemoteMedicationRecord]) {
//        todayMedicationRecords = newValue
//    }
//
//    @ViewBuilder
//    private func medicationPlanSheetContent(for destination: MedicationPlanSheetDestination) -> some View {
//        if let memberID {
//            MedicationPlanFormView(
//                mode: destination.formMode,
//                memberID: memberID,
//                medicineBoxes: medicineBoxes,
//                workflowAPI: workflowAPI,
//                fileTransferService: fileTransferService,
//                notificationClient: notificationClient,
//                onMedicineBoxSaved: upsertMedicineBox,
//                onServerSaved: upsertMedicationPlan
//            )
//        } else {
//            Text(L10n.text("home.medical.list.medications.select_member_first", fallback: "请先选择成员"))
//                .font(.headline)
//                .foregroundStyle(.secondary)
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
//        }
//    }
//
//    private var uploadHostView: some View {
//        CompatibleNavigationContainer {
//            MedicalDocumentUploadHostView(
//                viewModel: medicalDocumentUploadViewModel,
//                aiSettingsViewModel: aiSettingsViewModel
//            )
//        }
//    }
//
//    private var executionCenterToolbarLink: some View {
//        MainNavigationLink {
//            MedicationExecutionCenterPage(
//                medicationPlans: medicationPlans,
//                medicineBoxes: medicineBoxes,
//                initialRecords: todayMedicationRecords,
//                memberID: memberID,
//                medicalQueryAPI: medicalQueryAPI,
//                workflowAPI: workflowAPI,
//                fileTransferService: fileTransferService,
//                notificationClient: notificationClient,
//                logger: logger,
//                completeData: completeData,
//                memberContextStore: memberContextStore,
//                medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
//                aiSettingsViewModel: aiSettingsViewModel,
//                onMedicationPlansChanged: onMedicationPlansChanged,
//                onPrescriptionsChanged: onPrescriptionsChanged,
//                onMedicineBoxesChanged: updateMedicineBoxes
//            )
//        } label: {
//            Label(L10n.text("home.medical.list.medications.action.execution_center", fallback: "执行"), systemImage: "checklist.checked")
//                .font(.footnote.weight(.semibold))
//        }
//        .disabled(memberID == nil)
//    }
//
//    @ViewBuilder
//    private var medicineBoxToolbarLink: some View {
//        // 个人药箱入口：复用 FamilyMedicineCabinetPage 的 personal 模式
//        if let memberID, let homeDependencies {
//            MainNavigationLink {
//                FamilyMedicineCabinetPage(
//                    entryMemberID: memberID,
//                    mode: .personal,
//                    initialMedicineBoxes: medicineBoxes,
//                    dependencies: homeDependencies,
//                    onMedicineBoxesChanged: updateMedicineBoxes
//                )
//            } label: {
//                Label(L10n.text("home.medical.list.medications.action.medicine_box", fallback: "药箱"), systemImage: "pills.fill")
//                    .font(.footnote.weight(.semibold))
//            }
//        }
//    }
//
//    private var filterTabBar: some View {
//        HStack(spacing: 0) {
//            ForEach(MedicationFilterType.allCases) { filter in
//                Button {
//                    selectedFilter = filter
//                } label: {
//                    VStack(spacing: 8) {
//                        Text(filter.title)
//                            .font(selectedFilter == filter ? .subheadline.weight(.semibold) : .subheadline)
//                            .foregroundStyle(
//                                selectedFilter == filter
//                                ? Color(uiColor: .systemBlue)
//                                : Color(uiColor: .systemBlue).opacity(0.6)
//                            )
//
//                        Rectangle()
//                            .fill(selectedFilter == filter ? Color(uiColor: .systemBlue) : Color.clear)
//                            .frame(height: 2)
//                            .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
//                    }
//                    .frame(maxWidth: .infinity)
//                    .contentShape(Rectangle())
//                }
//                .buttonStyle(.plain)
//            }
//        }
//        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedFilter)
//    }
//
//    private var medicationScrollableContent: some View {
//        ScrollView {
//            if filteredItems.isEmpty {
//                emptyStateView
//                    .frame(maxWidth: .infinity, minHeight: 360)
//                    .padding(.vertical, 24)
//            } else {
//                LazyVStack(spacing: 0) {
//                    ForEach(filteredItems) { item in
//                        switch item {
//                        case .prescription(_, let prescription, let plans):
//                            MainNavigationLink {
//                                MedicationPrescriptionDetailPage(
//                                    prescription: prescription,
//                                    plans: plans,
//                                    medicineBoxes: medicineBoxes,
//                                    recordsByPlanID: recordsByPlanID,
//                                    memberID: memberID,
//                                    completeData: completeData,
//                                    memberContextStore: memberContextStore,
//                                    workflowAPI: workflowAPI,
//                                    fileTransferService: fileTransferService,
//                                    notificationClient: notificationClient,
//                                    onPrescriptionSaved: upsertPrescription,
//                                    onPrescriptionDeleted: removePrescription,
//                                    onPlanSaved: upsertMedicationPlan,
//                                    onPlanDeleted: removeMedicationPlan
//                                )
//                            } label: {
//                                MedicationPrescriptionCard(
//                                    prescription: prescription,
//                                    plans: plans,
//                                    medicineBoxesByID: medicineBoxesByID,
//                                    recordsByPlanID: recordsByPlanID,
//                                    fileTransferService: fileTransferService,
//                                    planDestination: planDetailPage
//                                )
//                            }
//                            .buttonStyle(.plain)
//                            .padding(.horizontal, 16)
//                            .padding(.vertical, 8)
//                        case .standalonePlan(let plan):
//                            MainNavigationLink {
//                                planDetailPage(for: plan)
//                            } label: {
//                                MedicationPlanCard(
//                                    plan: plan,
//                                    medicineBox: plan.medicineBox.flatMap { medicineBoxesByID[$0] },
//                                    records: recordsByPlanID[plan.id] ?? [],
//                                    fileTransferService: fileTransferService
//                                )
//                            }
//                            .buttonStyle(.plain)
//                            .padding(.horizontal, 16)
//                            .padding(.vertical, 8)
//                        }
//                    }
//
//                    Text(L10n.text("home.medical.list.medications.footer.no_more", fallback: "没有更多了"))
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
//                        .padding(.top, 8)
//                        .padding(.bottom, 96)
//                }
//            }
//        }
//        .refreshable {
//            await refreshMedicationPlans()
//        }
//    }
//
//    private func planDetailPage(for plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> some View {
//        MedicationPlanDetailPage(
//            plan: plan,
//            medicineBoxes: medicineBoxes,
//            records: recordsByPlanID[plan.id] ?? [],
//            memberID: memberID,
//            completeData: completeData,
//            memberContextStore: memberContextStore,
//            workflowAPI: workflowAPI,
//            fileTransferService: fileTransferService,
//            notificationClient: notificationClient,
//            onSaved: upsertMedicationPlan,
//            onDeleted: removeMedicationPlan,
//            onMedicineBoxSaved: upsertMedicineBox,
//            onMedicineBoxDeleted: removeMedicineBoxFromList
//        )
//    }
//
//    private var emptyStateView: some View {
//        VStack(spacing: 16) {
//            Image(systemName: "calendar.badge.clock")
//                .font(.largeTitle)
//                .foregroundStyle(.secondary)
//
//            Text(L10n.text("home.medical.list.medications.empty.title", fallback: "暂无服药计划"))
//                .font(.headline)
//                .foregroundStyle(.secondary)
//
//            Text(L10n.text("home.medical.list.medications.empty.subtitle", fallback: "创建服药计划后，可按时间、剂量和频次跟踪。"))
//                .font(.subheadline)
//                .foregroundStyle(.secondary)
//                .multilineTextAlignment(.center)
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .padding(.horizontal, 24)
//    }
//
//    private func upsertMedicationPlan(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) {
//        if let index = medicationPlans.firstIndex(where: { $0.id == plan.id }) {
//            medicationPlans[index] = plan
//        } else {
//            medicationPlans.insert(plan, at: 0)
//        }
//        onMedicationPlansChanged?(medicationPlans)
//        notifyMedicationPlanChanged(plan)
//        sheetDestination = nil
//    }
//
//    private func removeMedicationPlan(id: Int) {
//        medicationPlans.removeAll { $0.id == id }
//        onMedicationPlansChanged?(medicationPlans)
//        notifyMedicationPlanChanged(nil)
//    }
//
//    private func notifyMedicationPlanChanged(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan?) {
//        guard let homeDependencies else { return }
//        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
//
//        let members = memberContextStore.context.members
//        let coordinator = homeDependencies.medicationReminderSyncCoordinator
//        coordinator.activate(accountID: session.accountID)
//
//        guard plan?.reminderEnabled == true else {
//            coordinator.rebuildAfterPlanChanged(accountID: session.accountID, members: members)
//            return
//        }
//
//        Task {
//            let status = await coordinator.permissionCoordinatorAccess.currentStatus()
//            if status == .notDetermined {
//                showMedicationReminderPermissionExplanation = true
//                return
//            }
//            coordinator.rebuildAfterPlanChanged(accountID: session.accountID, members: members)
//        }
//    }
//
//    private func confirmMedicationReminderPermissionRequest() {
//        guard let homeDependencies else { return }
//        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
//        Task {
//            await homeDependencies.medicationReminderSyncCoordinator.requestSystemPermissionAndRebuild(
//                accountID: session.accountID,
//                members: memberContextStore.context.members
//            )
//        }
//    }
//
//    private func skipMedicationReminderPermissionRequest() {
//        guard let homeDependencies else { return }
//        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
//        notificationClient.info(
//            L10n.text("medication_reminder.permission.skipped_toast"),
//            title: L10n.text("medication_reminder.title"),
//            source: "medication_reminder"
//        )
//        homeDependencies.medicationReminderSyncCoordinator.rebuildAfterPlanChanged(
//            accountID: session.accountID,
//            members: memberContextStore.context.members
//        )
//    }
//
//    private func upsertPrescription(_ prescription: SparkMedicalSyncAPI.RemotePrescription) {
//        if let index = prescriptions.firstIndex(where: { $0.id == prescription.id }) {
//            prescriptions[index] = prescription
//        } else {
//            prescriptions.insert(prescription, at: 0)
//        }
//        onPrescriptionsChanged?(prescriptions)
//    }
//
//    private func removePrescription(id: Int) {
//        prescriptions.removeAll { $0.id == id }
//        onPrescriptionsChanged?(prescriptions)
//    }
//
//    private func upsertMedicineBox(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
//        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
//            medicineBoxes[index] = box
//        } else {
//            medicineBoxes.insert(box, at: 0)
//        }
//        onMedicineBoxesChanged?(medicineBoxes)
//    }
//
//    private func removeMedicineBoxFromList(_ id: Int) {
//        medicineBoxes.removeAll { $0.id == id }
//        onMedicineBoxesChanged?(medicineBoxes)
//    }
//
//    private func updateMedicineBoxes(_ boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]) {
//        medicineBoxes = boxes
//        onMedicineBoxesChanged?(boxes)
//    }
//
//    @MainActor
//    private func refreshMedicationPlans() async {
//        guard let memberID else {
//            logger.warning("服药计划下拉刷新跳过：缺少成员 ID", module: logModule)
//            return
//        }
//
//        let startedAt = Date()
//        logger.info("服药计划下拉刷新开始 memberID=\(memberID)", module: logModule)
//
//        do {
//            async let refreshedPlans = medicalQueryAPI.listMedicationPlans(memberID: memberID)
//            async let refreshedPrescriptions = medicalQueryAPI.listPrescriptions(memberID: memberID)
//            let (plans, prescriptionRows) = try await (refreshedPlans, refreshedPrescriptions)
//            medicationPlans = plans
//            prescriptions = prescriptionRows
//            onMedicationPlansChanged?(plans)
//            onPrescriptionsChanged?(prescriptionRows)
//            logger.info(
//                "服药计划下拉刷新完成 memberID=\(memberID) plans=\(plans.count) prescriptions=\(prescriptionRows.count) cost=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s",
//                module: logModule
//            )
//        } catch {
//            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.medication_plans.refresh")
//            logger.warning("服药计划下拉刷新失败 memberID=\(memberID) error=\(error.localizedDescription)", module: logModule)
//        }
//    }
//
//    @MainActor
//    private func refreshAfterMedicalUploadSave() async {
//        await refreshMedicationPlans()
//        guard let memberID else { return }
//        do {
//            let boxes = try await medicalQueryAPI.listMedicineBoxes(memberID: memberID)
//            medicineBoxes = boxes
//            onMedicineBoxesChanged?(boxes)
//        } catch {
//            logger.warning("AI 保存后刷新药箱失败 memberID=\(memberID) error=\(error.localizedDescription)", module: logModule)
//        }
//    }
//
//    @MainActor
//    private func startMedicationPlanRecognition(files: [MedicalUploadLocalFile]) {
//        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .medicationPlan)
//    }
//
//    private func statusRank(_ status: String) -> Int {
//        switch status {
//        case "active":
//            return 0
//        case "paused":
//            return 1
//        case "completed":
//            return 2
//        case "cancelled":
//            return 3
//        default:
//            return 4
//        }
//    }
//
//    private func isPlanInDateRange(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> Bool {
//        plan.startDate <= today && isPlanEnded(plan) == false
//    }
//
//    private func isPlanEnded(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> Bool {
//        guard let endDate = plan.endDate else {
//            return false
//        }
//        return endDate < today
//    }
//}

private extension MedicationListItem {
    var plans: [SparkMedicalSyncAPI.RemoteMedicationPlan] {
        switch self {
        case .prescription(_, _, let plans):
            return plans
        case .standalonePlan(let plan):
            return [plan]
        }
    }
}

private enum MedicationPlanSheetDestination: Identifiable {
    case create
    case serverEdit(SparkMedicalSyncAPI.RemoteMedicationPlan)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .serverEdit(let plan):
            return "server_\(plan.id)"
        }
    }

    var formMode: MedicationPlanFormView.Mode {
        switch self {
        case .create:
            return .create
        case .serverEdit(let plan):
            return .serverEdit(existing: plan)
        }
    }
}

// MARK: - Medication plan dose (detail sheet)

private struct MedicationPlanDoseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
//    @Binding var doseValue: String
    @Binding var doseUnit: String
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]

    @State private var tempDoseValue = ""
    @State private var tempDoseUnit = ""
    @FocusState private var doseValueFocused: Bool

    private static let selectedChip = Color(red: 79 / 255, green: 70 / 255, blue: 229 / 255)
    private static let sheetHeaderChromeHeight: CGFloat = 72
    private static let sheetFooterChromeHeight: CGFloat = 88

    private var doseUnitLabels: [String] {
        MedicineSpecificationCatalog.doseUnitMenuOptions(boxes: specOptionBoxes)
    }

    private var prefersEnglish: Bool {
        SparkFormCatalogMenuLocale.prefersEnglish
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    }

    private var trimmedTempDoseUnit: String {
        tempDoseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        CompatibleNavigationContainer {
            AdaptiveToolSheetScrollView(
                bottomContentPadding: 12,
                extraChromeHeight: Self.sheetHeaderChromeHeight + Self.sheetFooterChromeHeight
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    sheetFieldBlock(title: L10n.text("medical_record.medicine_box.spec.dose_value")) {
                        HStack(spacing: prefersEnglish ? 6 : 0) {
                            TextField("5", text: doseValueBinding)
                                .textFieldStyle(.plain)
                                .focused($doseValueFocused)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)

                            if trimmedTempDoseUnit.isEmpty == false {
                                Text(MedicineSpecificationCatalog.displayUnit(stored: trimmedTempDoseUnit, prefersEnglish: prefersEnglish))
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.secondary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    unitChipBlock(
                        title: L10n.text("medical_record.medicine_box.spec.dose_unit"),
                        labels: doseUnitLabels,
                        isSelected: { label in
                            MedicineSpecificationCatalog.storedDoseUnit(fromDisplay: label)
                            == MedicineSpecificationCatalog.storedDoseUnit(fromAny: tempDoseUnit)
                        },
                        onSelect: { label in
                            tempDoseUnit = MedicineSpecificationCatalog.storedDoseUnit(fromDisplay: label)
                        }
                    )
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .navigationTitle(L10n.text("medication_plan.form.single_dose_value_sheet_title", fallback: "单次剂量数值"))
            .navigationBarTitleDisplayMode(.inline)
            .sparkKeyboardDoneToolbar {
                SparkKeyboardDismiss.endEditing()
            }
            .sparkFormBottomBar(
                canSubmit: true,
                cancelTitle: L10n.text("common.cancel"),
                saveTitle: L10n.text("common.done"),
                saveSystemImage: "checkmark.circle.fill",
                onCancel: {
                    dismiss()
                },
                onSave: {
                    doseUnit = tempDoseValue + tempDoseUnit
                    dismiss()
                }
            )
        }
        .ignoresSafeArea()
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            let parts = MedicineSpecification.doseValueAndStoredUnit(fromBackendDoseUnitField: doseUnit)
            tempDoseValue = parts.value
            tempDoseUnit = parts.unit
        }
    }

    private var doseValueBinding: Binding<String> {
        Binding(
            get: { tempDoseValue },
            set: { tempDoseValue = $0 }
        )
    }

    private func sheetFieldBlock(title: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            field()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator).opacity(0.35))
        }
    }

    private func unitChipBlock(
        title: String,
        labels: [String],
        isSelected: @escaping (String) -> Bool,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .padding(.top, 16)

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(labels, id: \.self) { label in
                    let selected = isSelected(label)
                    Button {
                        onSelect(label)
                    } label: {
                        Text(label)
                            .font(.system(size: 14))
                            .foregroundColor(selected ? .white : Color.primary.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)
                            .background(selected ? Self.selectedChip : Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator).opacity(0.35))
        }
    }
}

struct MedicationPlanFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: SparkMedicalSyncAPI.RemoteMedicationPlan)
        case localEdit(existing: MedicationPlanDraft, onSubmit: (MedicationPlanDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let memberID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let notificationClient: any NotificationClient
    let onMedicineBoxSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    let onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void)?

    @State private var draft: MedicationPlanDraft
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @State private var sheetKeyboardVisible = false
    @State private var showReminderFrequencySheet = false
    @State private var showDoseDetailSheet = false
    /// Last `dosePerTime` produced from `doseValue`/`doseUnit`; used to avoid overwriting custom user text.
    @State private var lastAutoSuggestedDosePerTime: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    /// 在测量的滚动内容（内嵌导航 + sparkFormBottomBar ）外的 Chrome 浏览器，与 MedicineBoxFormView 的分离数学对齐。
    private static let formSheetNavChromeHeight: CGFloat = 72
    private static let formSheetBottomBarChromeHeight: CGFloat = 88

    init(
        mode: Mode,
        memberID: Int,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        onMedicineBoxSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void)? = nil
    ) {
        self.mode = mode
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
        self.onMedicineBoxSaved = onMedicineBoxSaved
        self.onServerSaved = onServerSaved
        _medicineBoxes = State(initialValue: medicineBoxes)

        switch mode {
        case .create:
            _draft = State(initialValue: MedicationPlanDraft())
        case .serverEdit(let existing):
            _draft = State(initialValue: MedicationPlanDraft(existing: existing))
        case .localEdit(let existing, _):
            _draft = State(initialValue: existing)
        }
    }

    private var selectedMedicineBox: SparkMedicalSyncAPI.RemoteMedicineBox? {
        guard let medicineBoxID = draft.medicineBoxID else { return nil }
        return medicineBoxes.first(where: { $0.id == medicineBoxID })
    }

    private var canSubmit: Bool {
        isSubmitting == false
        && draft.drugName.nilIfBlank != nil
        && draft.dosePerTime.nilIfBlank != nil
        && draft.isReminderFrequencyComplete
        && draft.resolvedFrequencyText.nilIfBlank != nil
        && draft.reminderTimesError == nil
        && (draft.hasEndDate == false || draft.endDate >= draft.startDate)
    }

    private var navigationTitle: String {
        switch mode {
        case .create:
            return L10n.text("medication_plan.form.create_title", fallback: "新增服药计划")
        case .serverEdit, .localEdit:
            return L10n.text("medication_plan.form.edit_title", fallback: "编辑服药计划")
        }
    }

    var body: some View {
        CompatibleNavigationContainer {
            formContent
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .sparkFormBottomBar(
                    canSubmit: canSubmit,
                    cancelTitle: L10n.text("common.cancel"),
                    saveTitle: L10n.text("common.done"),
                    saveSystemImage: "checkmark.circle.fill",
                    keyboardVisible: $sheetKeyboardVisible,
                    onCancel: {
                        formLog.info("MedicationPlanFormView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
                        dismiss()
                    },
                    onSave: {
                        guard canSubmit else { return }
                        submitDraft()
                    }
                )
        }
        .background(Color(uiColor: .systemBackground))
        .interactiveDismissDisabled(isSubmitting)
        .alert(L10n.text("medication_plan.form.save_failed", fallback: "保存失败"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button(L10n.text("common.got_it"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: $showReminderFrequencySheet) {
            MedicationReminderFrequencySheet(
                type: draft.reminderFrequencyType,
                everyNDays: draft.everyNDays,
                weekdays: draft.weeklyWeekdays,
                summaryText: draft.frequencyText
            ) { type, everyN, weekdays, text in
                draft.reminderFrequencyType = type
                draft.everyNDays = everyN
                draft.weeklyWeekdays = weekdays
                draft.frequencyText = text
            }
        }
        .sheet(isPresented: $showDoseDetailSheet) {
            MedicationPlanDoseDetailSheet(
                doseUnit: $draft.doseUnit,
                specOptionBoxes: medicineBoxes
            )
        }
        .onAppear {
            syncDosePerTimeWithDoseFields()
        }
        .onChange(of: draft.doseValue) { _ in
            syncDosePerTimeWithDoseFields()
        }
        .onChange(of: draft.doseUnit) { _ in
            syncDosePerTimeWithDoseFields()
        }
    }

    private func currentSuggestedDosePerTimeLine() -> String {
        MedicationPlanDraft.suggestedDosePerTimeLine(
            doseValue: draft.doseValue,
            doseUnit: draft.doseUnit,
            prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish
        )
    }

    private func syncDosePerTimeWithDoseFields() {
        let suggested = currentSuggestedDosePerTimeLine()
        let cur = draft.dosePerTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastAutoSuggestedDosePerTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldApply = cur.isEmpty || last.map { cur == $0 } == true
        if shouldApply, draft.dosePerTime != suggested {
            draft.dosePerTime = suggested
        }
        lastAutoSuggestedDosePerTime = suggested
    }

    private var formContent: some View {
        AdaptiveToolSheetScrollView(
            bottomContentPadding: 0,
            extraChromeHeight: Self.formSheetNavChromeHeight + Self.formSheetBottomBarChromeHeight
        ) {
            VStack(spacing: 14) {
                SparkFormCard(title: L10n.text("medication_plan.form.section.linked_medicine", fallback: "关联药品"), titleSystemImage: "pills.fill") {
                    MainNavigationLink {
                        MedicationPlanMedicineBoxPickerPage(
                            memberID: memberID,
                            medicineBoxes: medicineBoxes,
                            selectedMedicineBoxID: draft.medicineBoxID,
                            workflowAPI: workflowAPI,
                            fileTransferService: fileTransferService,
                            onMedicineBoxSaved: handleMedicineBoxSaved,
                            onSelect: applyMedicineBoxSelection
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox.fill")
                                .font(.headline)
                                .foregroundStyle(Color(uiColor: .systemPurple))
                                .frame(width: 36, height: 36)
                                .background(Color(uiColor: .systemPurple).opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(selectedMedicineBoxTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(selectedMedicineBoxSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                

                SparkFormCard(title: L10n.text("medication_plan.form.section.rules", fallback: "用药规则"), titleSystemImage: "calendar.badge.clock") {
                    VStack(spacing: 16) {
                        SparkFormTextRow(
                            title: L10n.text("medication_plan.form.field.drug_name", fallback: "药品名称"),
                            text: $draft.drugName,
                            placeholder: L10n.text("medication_plan.form.drug_name_placeholder", fallback: "如 阿莫西林胶囊"),
                            required: true,
                            keyboardVisible: $sheetKeyboardVisible
                        )
                                                
                        
                        HStack(spacing: 12) {
                            MedicationPlanDoseValueStepperRow(
                                text: $draft.doseValue,
                                keyboardVisible: $sheetKeyboardVisible,
                                controlStyle: .custom
                            )

                            SparkFormSheetPickerRow(
                                title: L10n.text("medication_plan.form.single_dose_unit_sheet_title", fallback: "单次剂量单位"),
                                displayValue: draft.doseUnit,
                                placeholder: L10n.text("medication_plan.form.single_dose_sheet_placeholder", fallback: "设置单次剂量数值与单位"),
                                onTap: {
                                    showDoseDetailSheet = true
                                }
                            )
                        }
//                            SparkFormTextRow(title: "单次剂量说明", text: $draft.dosePerTime, placeholder: "如 1片 / 5ml", required: true, keyboardVisible: $sheetKeyboardVisible)
                        
                           SparkFormSheetPickerRow(
                               title: L10n.text("medication_plan.form.field.frequency", fallback: "服药频次"),
                               displayValue: draft.reminderFrequencyPickerDisplay,
                               placeholder: L10n.text("medication_plan.form.frequency_placeholder", fallback: "请选择提醒频率"),
                               required: true,
                               showsValidationError: draft.isReminderFrequencyComplete == false
                                   || draft.resolvedFrequencyText.nilIfBlank == nil
                           ) {
                               showReminderFrequencySheet = true
                           }
                        
                        
                           if #available(iOS 16.0, *) {
                               MedicationReminderTimesSection(draft: $draft, notificationClient: notificationClient)
                           } else {
                               SparkFormCard(title: L10n.text("medication_plan.form.section.reminder_times", fallback: "提醒时间"), titleSystemImage: "calendar") {
                                   SparkFormTextRow(
                                       title: L10n.text("medication_plan.form.field.reminder_times", fallback: "提醒时间"),
                                       text: $draft.reminderTimesText,
                                       placeholder: L10n.text("medication_plan.form.reminder_times_placeholder", fallback: "如 08:00, 12:00, 20:00"),
                                       keyboardVisible: $sheetKeyboardVisible
                                   )
                                   if let reminderTimesError = draft.reminderTimesError {
                                       Text(reminderTimesError)
                                           .font(.caption)
                                           .foregroundStyle(Color(uiColor: .systemRed))
                                           .frame(maxWidth: .infinity, alignment: .leading)
                                   }
                               }
                           }

                        SparkFormTextAreaRow(
                            title: L10n.text("medication_plan.form.field.instructions", fallback: "用药说明"),
                            text: $draft.instructions,
                            minHeight: 80,
                            maxHeight: 160,
                            placeholder: L10n.text("medication_plan.form.instructions_placeholder", fallback: "饭前/饭后、禁忌或医嘱备注"),
                            keyboardVisible: $sheetKeyboardVisible
                        )
                    }
                }
                DisclosureGroup(
                    content: {
                        VStack(spacing: 16) {
                            SparkFormCard(title: L10n.text("medication_plan.form.section.course", fallback: "疗程"), titleSystemImage: "calendar") {
                                VStack(spacing: 12) {
                                    DatePicker(L10n.text("medication_plan.form.field.start_date", fallback: "开始日期"), selection: $draft.startDate, displayedComponents: .date)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .frame(height: 44)
                                        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Toggle(L10n.text("medication_plan.form.field.set_end_date", fallback: "设置结束日期"), isOn: $draft.hasEndDate)
                                        .font(.subheadline.weight(.medium))
                                    if draft.hasEndDate {
                                        DatePicker(L10n.text("medication_plan.form.field.end_date", fallback: "结束日期"), selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                                            .font(.subheadline.weight(.medium))
                                            .padding(.horizontal, 12)
                                            .frame(height: 44)
                                            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                            }

                            SparkFormCard(title: L10n.text("medication_plan.form.section.status_reminder", fallback: "状态与提醒"), titleSystemImage: "bell.badge.fill") {
                                VStack(spacing: 12) {
                                    Toggle(L10n.text("medication_plan.form.field.reminder_enabled", fallback: "开启提醒"), isOn: $draft.reminderEnabled)
                                        .font(.subheadline.weight(.medium))
                                    Picker(L10n.text("medication_plan.form.field.status", fallback: "计划状态"), selection: $draft.status) {
                                        Text(planStatusText("active")).tag("active")
                                        Text(L10n.text("home.medical.list.medications.status.paused_explicit", fallback: "已暂停")).tag("paused")
                                        Text(planStatusText("completed")).tag("completed")
                                        Text(planStatusText("cancelled")).tag("cancelled")
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    },
                    label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                            Text(L10n.text("medication_plan.form.section.course_reminder", fallback: "疗程与提醒"))
                                .font(.headline)

                        }
                    }
                )
                .padding(14)

            }
        }
    }

    private var selectedMedicineBoxTitle: String {
        selectedMedicineBox.map { $0.medicineName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed", fallback: "未命名药品") }
        ?? L10n.text("medication_plan.form.select_medicine_box", fallback: "选择药箱药品")
    }

    private var selectedMedicineBoxSubtitle: String {
        guard let selectedMedicineBox else {
            return L10n.text("medication_plan.form.select_medicine_box_subtitle", fallback: "可从药箱选择，也可在选择页新增药品")
        }
        let detail = [selectedMedicineBox.strength.nilIfBlank, selectedMedicineBox.dosageForm.nilIfBlank, stockText(selectedMedicineBox)]
            .compactMap { $0 }
            .joined(separator: " · ")
        return detail.isEmpty ? L10n.text("medication_plan.form.linked_medicine_box", fallback: "已关联药箱药品") : detail
    }

//    private var medicationPlanDoseDetailDisplay: String {
//        let dv = draft.doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
//        let du = draft.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
//        let pref = SparkFormCatalogMenuLocale.prefersEnglish
//        let unitDisplay = du.isEmpty ? "" : MedicineSpecificationCatalog.displayUnit(stored: du, prefersEnglish: pref)
//        if dv.isEmpty, du.isEmpty { return "" }
//        if dv.isEmpty { return unitDisplay }
//        if du.isEmpty { return dv }
//        return pref ? "\(dv) \(unitDisplay)" : "\(dv)\(unitDisplay)"
//    }

    private func handleMedicineBoxSaved(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
            medicineBoxes[index] = box
        } else {
            medicineBoxes.insert(box, at: 0)
        }
        onMedicineBoxSaved(box)
    }

    private func applyMedicineBoxSelection(_ box: SparkMedicalSyncAPI.RemoteMedicineBox?) {
        draft.medicineBoxID = box?.id
        guard let box else { return }
        if draft.drugName.nilIfBlank == nil {
            draft.drugName = box.medicineName
        }
        let apiDose = box.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiDose.isEmpty {
            draft.doseUnit = apiDose
        }
    }

    private func submitDraft() {
        switch mode {
        case .localEdit(_, let onSubmit):
            guard validateDraft() else { return }
            onSubmit(draft)
            dismiss()
        case .create, .serverEdit:
            Task { await submitToServer() }
        }
    }

    @MainActor
    private func submitToServer() async {
        guard validateDraft(), isSubmitting == false else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let payload = try draft.payload(memberID: memberID)
            let saved: SparkMedicalSyncAPI.RemoteMedicationPlan
            switch mode {
            case .create:
                saved = try await workflowAPI.create(
                    SparkMedicalSyncAPI.RemoteMedicationPlan.self,
                    kind: .medicationPlans,
                    body: payload
                )
            case .serverEdit(let existing):
                saved = try await workflowAPI.update(
                    SparkMedicalSyncAPI.RemoteMedicationPlan.self,
                    kind: .medicationPlans,
                    id: existing.id,
                    body: payload
                )
            case .localEdit:
                return
            }
            onServerSaved?(saved)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func validateDraft() -> Bool {
        guard canSubmit else {
            alertMessage = draft.validationMessage
            return false
        }
        return true
    }

    private var modeLogLabel: String {
        switch mode {
        case .create:
            return "create"
        case .serverEdit:
            return "serverEdit"
        case .localEdit:
            return "localEdit"
        }
    }
}

private enum MedicationReminderTimePickerRoute: Identifiable {
    case add
    case edit(index: Int)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let index):
            return "edit_\(index)"
        }
    }
}

@available(iOS 16.0, *)
private struct MedicationReminderTimePickerSheet: View {
    @Binding var selectedTime: Date
    let onConfirm: () -> Void
    @State private var tempTime: Date

    init(selectedTime: Binding<Date>, onConfirm: @escaping () -> Void) {
        self._selectedTime = selectedTime
        self.onConfirm = onConfirm
        self._tempTime = State(initialValue: selectedTime.wrappedValue)
    }

    var body: some View {
        AdaptiveSheetContainer.fixed(
            height: 260,
            onCancel: {},
            onConfirm: {
                selectedTime = tempTime
                onConfirm()
            }
        ) {
            DatePicker(
                "",
                selection: $tempTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

@available(iOS 16.0, *)
private struct MedicationReminderTimesSection: View {
    @Binding var draft: MedicationPlanDraft
    let notificationClient: any NotificationClient

    @State private var timePickerRoute: MedicationReminderTimePickerRoute?
    @State private var timePickerSelection = Date()

    private var slots: [String] {
        draft.orderedReminderTimeSlots
    }

    private var countSubtitle: String {
        let n = slots.count
        return String(format: L10n.text("medication_plan.form.reminder_times.count_per_day", fallback: "%d times/day"), locale: .current, n)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("medication_plan.form.field.medication_times", fallback: "用药时间"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 12)
                Text(countSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        timePickerSelection = defaultTimeForNewSlot()
                        timePickerRoute = .add
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 40, height: 40)
                            .background(Color(uiColor: .systemBackground), in: Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("medication_plan.form.a11y.add_medication_time", fallback: "新增用药时间"))

                    ForEach(Array(slots.enumerated()), id: \.offset) { index, time in
                        Menu {
                            Button {
                                timePickerSelection = MedicationPlanDraft.dateForReminderTimeToken(time)
                                timePickerRoute = .edit(index: index)
                            } label: {
                                Label(L10n.text("common.edit"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                removeSlot(at: index)
                            } label: {
                                Label(L10n.text("common.delete"), systemImage: "trash")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(time)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(uiColor: .systemBackground), in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                            )
                        }
                        .accessibilityLabel(String(format: L10n.text("medication_plan.form.a11y.medication_time_format", fallback: "Medication time %@"), locale: .current, time))
                    }
                }
                .padding(.vertical, 2)
            }

            if let reminderTimesError = draft.reminderTimesError {
                Text(reminderTimesError)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemRed))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 4)
        .sheet(item: $timePickerRoute) { route in
            MedicationReminderTimePickerSheet(selectedTime: $timePickerSelection) {
                applyPickedTime(route: route)
            }
        }
    }

    private func defaultTimeForNewSlot() -> Date {
        if let last = slots.last {
            return MedicationPlanDraft.dateForReminderTimeToken(last)
        }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 8
        c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }

    private func applyPickedTime(route: MedicationReminderTimePickerRoute) {
        let picked = MedicationPlanDraft.reminderTimeString(from: timePickerSelection)
        guard MedicationPlanDraft.isValidTimeText(picked) else { return }

        var next = slots
        switch route {
        case .add:
            if next.contains(picked) {
                notificationClient.warning(
                    L10n.text("medication_plan.form.reminder_times.duplicate", fallback: "该提醒时间已存在"),
                    source: "medication.plan.reminder_times"
                )
                return
            }
            next.append(picked)
        case .edit(let index):
            guard next.indices.contains(index) else { return }
            if let dup = next.firstIndex(of: picked), dup != index {
                notificationClient.warning(
                    L10n.text("medication_plan.form.reminder_times.duplicate", fallback: "该提醒时间已存在"),
                    source: "medication.plan.reminder_times"
                )
                return
            }
            next[index] = picked
        }
        draft.replaceReminderTimeSlots(next)
    }

    private func removeSlot(at index: Int) {
        var next = slots
        guard next.indices.contains(index) else { return }
        next.remove(at: index)
        draft.replaceReminderTimeSlots(next)
    }
}

private struct MedicationPlanMedicineBoxPickerPage: View {
    let memberID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let onMedicineBoxSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    let onSelect: (SparkMedicalSyncAPI.RemoteMedicineBox?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var selectedMedicineBoxID: Int?
    @State private var sheetDestination: MedicineBoxSheetDestination?

    init(
        memberID: Int,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        selectedMedicineBoxID: Int?,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        onMedicineBoxSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onSelect: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox?) -> Void
    ) {
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.onMedicineBoxSaved = onMedicineBoxSaved
        self.onSelect = onSelect
        _medicineBoxes = State(initialValue: medicineBoxes)
        _selectedMedicineBoxID = State(initialValue: selectedMedicineBoxID)
    }

    private var sortedBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] {
        medicineBoxes.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var medicineTypeOptions: [String] {
        MedicineBoxTypeCatalog.options(in: medicineBoxes)
    }

    private func medicineBoxStrengthListSubtitle(_ strength: String) -> String? {
        let raw = strength.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isEmpty == false else { return nil }
        let spec = MedicineSpecification.parse(fromAPIStrength: raw)
        if spec.hasStructuredContent {
            return spec.displayString(prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish)
        }
        return raw
    }

    var body: some View {
        List {
            Section {
                Button {
                    selectedMedicineBoxID = nil
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Label(L10n.text("medication_plan.medicine_box_picker.none", fallback: "不关联药箱药品"), systemImage: "link.badge.minus")
                        Spacer()
                        if selectedMedicineBoxID == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }

            Section(L10n.text("medication_plan.medicine_box_picker.section.medicines", fallback: "药箱药品")) {
                if sortedBoxes.isEmpty {
                    Text(L10n.text("medication_plan.medicine_box_picker.empty", fallback: "暂无药箱药品"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedBoxes, id: \.id) { box in
                        HStack(spacing: 12) {
                            Button {
                                selectedMedicineBoxID = box.id
                                onSelect(box)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(box.medicineName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed", fallback: "未命名药品"))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text([
                                            medicineBoxStrengthListSubtitle(box.strength),
                                            box.dosageForm.nilIfBlank,
                                            stockText(box)
                                        ].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if selectedMedicineBoxID == box.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                sheetDestination = .serverEdit(box)
                            } label: {
                                Image(systemName: "pencil.circle")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.text("medication_plan.medicine_box_picker.a11y.edit_medicine", fallback: "编辑药品"))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(L10n.text("medication_plan.medicine_box_picker.title", fallback: "选择药品"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sheetDestination = .create
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel(L10n.text("home.medical.medicine_box.add_a11y", fallback: "新增药品"))
            }
        }
        .sheet(item: $sheetDestination) { destination in
            MedicineBoxFormView(
                mode: destination.formMode,
                entryMemberID: memberID,
                defaultBindingMemberID: memberID,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                typeOptions: medicineTypeOptions,
                specOptionBoxes: medicineBoxes,
                onServerSaved: upsertMedicineBox
            )
        }
    }

    private func upsertMedicineBox(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
            medicineBoxes[index] = box
        } else {
            medicineBoxes.insert(box, at: 0)
        }
        onMedicineBoxSaved(box)
        selectedMedicineBoxID = box.id
        onSelect(box)
        sheetDestination = nil
    }
}

struct MedicationPlanDraft {
    var medicalCaseID: Int?
    var medicineBoxID: Int?
    var prescriptionID: Int?
    var drugName = ""
    var dosePerTime = ""
    var doseValue = ""
    var doseUnit = "片"
    var reminderFrequencyType: MedicationReminderFrequencyType = .daily
    var everyNDays: Int = 1
    var weeklyWeekdays: Set<Int> = []
    var frequencyText = ""
    var reminderTimesText = "08:00"
    var startDate = Date()
    var hasEndDate = false
    var endDate = Date()
    var instructions = ""
    var reminderEnabled = true
    var status = "active"

    init() {}

    init(existing: SparkMedicalSyncAPI.RemoteMedicationPlan) {
        medicalCaseID = existing.medicalCase
        medicineBoxID = existing.medicineBox
        prescriptionID = existing.prescription
        drugName = existing.drugName
        dosePerTime = existing.dosePerTime
        doseValue = existing.doseValue.map { $0.formatted(.number.precision(.fractionLength(0...3))) } ?? ""
        doseUnit = existing.doseUnit
        reminderFrequencyType = MedicationReminderFrequencyType(rawValue: existing.frequencyType) ?? .daily
        everyNDays = min(max(existing.everyNDays ?? 1, 1), 365)
        weeklyWeekdays = Set(existing.weeklyWeekdays.filter { (1...7).contains($0) })
        frequencyText = existing.frequencyText
        if frequencyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            frequencyText = MedicationReminderFrequencySummary.displayLine(
                type: reminderFrequencyType,
                everyNDays: everyNDays,
                weekdays: weeklyWeekdays
            )
        }
        reminderTimesText = existing.reminderTimes.map(\.time).joined(separator: ", ")
        startDate = existing.startDate
        if let endDate = existing.endDate {
            hasEndDate = true
            self.endDate = endDate
        }
        instructions = existing.instructions
        reminderEnabled = existing.reminderEnabled
        status = existing.status
    }

    var doseValueValue: Double? {
        doseValue.nilIfBlank.flatMap(Double.init)
    }

    /// Human-readable `dose_per_time` line from structured fields, e.g. `1 / 5 ml` when both are set.
    static func suggestedDosePerTimeLine(doseValue: String, doseUnit: String, prefersEnglish: Bool) -> String {
        let dv = doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let du = doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let duDisp = du.isEmpty ? "" : MedicineSpecificationCatalog.displayUnit(stored: du, prefersEnglish: prefersEnglish)
        switch (dv.isEmpty, duDisp.isEmpty) {
        case (true, true): return ""
        case (false, true): return dv
        case (true, false): return duDisp
        case (false, false): return "\(dv) / \(duDisp)"
        }
    }

    var isReminderFrequencyComplete: Bool {
        MedicationReminderFrequencySummary.isComplete(
            type: reminderFrequencyType,
            everyNDays: everyNDays,
            weekdays: weeklyWeekdays
        )
    }

    var resolvedFrequencyText: String {
        if let manual = frequencyText.nilIfBlank {
            return manual
        }
        return MedicationReminderFrequencySummary.displayLine(
            type: reminderFrequencyType,
            everyNDays: everyNDays,
            weekdays: weeklyWeekdays
        )
    }

    var reminderFrequencyPickerDisplay: String {
        let line = resolvedFrequencyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty == false { return line }
        return MedicationReminderFrequencySummary.displayLine(
            type: reminderFrequencyType,
            everyNDays: everyNDays,
            weekdays: weeklyWeekdays
        )
    }

    var reminderTimesError: String? {
        parseReminderTimes().error
    }

    var validationMessage: String {
        if drugName.nilIfBlank == nil {
            return L10n.text("medication_plan.form.validation.drug_name_required", fallback: "请填写药品名称")
        }
        if dosePerTime.nilIfBlank == nil {
            return L10n.text("medication_plan.form.validation.dose_required", fallback: "请填写单次剂量")
        }
        if isReminderFrequencyComplete == false {
            return L10n.text("medication_plan.form.validation.frequency_incomplete", fallback: "请完整选择服药频次（每几天需选天数，每周需至少选一天）")
        }
        if resolvedFrequencyText.nilIfBlank == nil {
            return L10n.text("medication_plan.form.validation.frequency_text_required", fallback: "请填写或生成服药频次说明")
        }
        if let reminderTimesError {
            return reminderTimesError
        }
        if hasEndDate && endDate < startDate {
            return L10n.text("medication_plan.form.validation.end_date_before_start", fallback: "结束日期不能早于开始日期")
        }
        return L10n.text("medication_plan.form.validation.incomplete", fallback: "请完善服药计划信息")
    }

    fileprivate func payload(memberID: Int) throws -> MedicationPlanPayload {
        let reminderTimesResult = parseReminderTimes()
        if let error = reminderTimesResult.error {
            throw MedicationPlanFormError.invalidReminderTimes(error)
        }
        let weeklyPayload: [Int] = {
            guard reminderFrequencyType == .weekly else { return [] }
            return weeklyWeekdays.filter { (1...7).contains($0) }.sorted()
        }()
        return MedicationPlanPayload(
            member: memberID,
            medicalCase: medicalCaseID,
            medicineBox: medicineBoxID,
            prescription: prescriptionID,
            drugName: drugName.trimmed,
            dosePerTime: dosePerTime.trimmed,
            doseValue: doseValueValue,
            doseUnit: doseUnit.nilIfBlank ?? "片",
            frequencyType: reminderFrequencyType.rawValue,
            everyNDays: reminderFrequencyType == .everyNDays ? everyNDays : nil,
            weeklyWeekdays: weeklyPayload,
            frequencyText: resolvedFrequencyText.trimmed,
            reminderTimes: reminderTimesResult.times,
            startDate: MedicalDateCoding.encodeDateOnly(startDate),
            endDate: hasEndDate ? MedicalDateCoding.encodeDateOnly(endDate) : nil,
            instructions: instructions.nilIfBlank ?? "",
            reminderEnabled: reminderEnabled,
            status: status,
            extra: [:]
        )
    }

    private func parseReminderTimes() -> (times: [ReminderTime], error: String?) {
        let rawItems = reminderTimesText
            .components(separatedBy: CharacterSet(charactersIn: ",，、;； \n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        var result: [ReminderTime] = []
        var seen = Set<String>()
        for item in rawItems {
            guard Self.isValidTimeText(item) else {
                return ([], L10n.text("medication_plan.form.validation.reminder_time_format", fallback: "提醒时间格式应为 HH:mm，例如 08:00"))
            }
            guard seen.insert(item).inserted else { continue }
            result.append(.init(time: item, dose: doseValueValue))
        }
        return (result, nil)
    }

    fileprivate static func isValidTimeText(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }
}

extension MedicationPlanDraft {
    /// 从当前文案中提取有效、去重后的 `HH:mm` 列表（用于用药时间 chips；无效片段被跳过，仍可由 `reminderTimesError` 提示整体验证）。
    fileprivate var orderedReminderTimeSlots: [String] {
        let rawItems = reminderTimesText
            .components(separatedBy: CharacterSet(charactersIn: ",，、;； \n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        var result: [String] = []
        var seen = Set<String>()
        for item in rawItems {
            guard Self.isValidTimeText(item) else { continue }
            let norm = Self.normalizedReminderTimeToken(item)
            guard seen.insert(norm).inserted else { continue }
            result.append(norm)
        }
        return result
    }

    fileprivate mutating func replaceReminderTimeSlots(_ slots: [String]) {
        var seen = Set<String>()
        var unique: [String] = []
        for slot in slots {
            let norm = Self.normalizedReminderTimeToken(slot)
            guard Self.isValidTimeText(norm) else { continue }
            if seen.insert(norm).inserted {
                unique.append(norm)
            }
        }
        unique.sort()
        reminderTimesText = unique.isEmpty ? "" : unique.joined(separator: ", ")
    }

    fileprivate static func normalizedReminderTimeToken(_ value: String) -> String {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    fileprivate static func reminderTimeString(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = min(max(c.hour ?? 0, 0), 23)
        let m = min(max(c.minute ?? 0, 0), 59)
        return String(format: "%02d:%02d", h, m)
    }

    fileprivate static func dateForReminderTimeToken(_ token: String) -> Date {
        let parts = token.split(separator: ":")
        let h = min(max(Int(parts[0]) ?? 8, 0), 23)
        let m = parts.count > 1 ? min(max(Int(parts[1]) ?? 0, 0), 59) : 0
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = h
        c.minute = m
        return Calendar.current.date(from: c) ?? Date()
    }
}

private struct MedicationPlanPayload: Encodable {
    let member: Int
    let medicalCase: Int?
    let medicineBox: Int?
    let prescription: Int?
    let drugName: String
    let dosePerTime: String
    let doseValue: Double?
    let doseUnit: String
    let frequencyType: String
    let everyNDays: Int?
    let weeklyWeekdays: [Int]
    let frequencyText: String
    let reminderTimes: [ReminderTime]
    let startDate: String
    let endDate: String?
    let instructions: String
    let reminderEnabled: Bool
    let status: String
    let extra: [String: String]


    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodableKey.self)
        try container.encode(member, forKey: .key("member"))
        try container.encodeNullable(medicalCase, forKey: .key("medicalCase"))
        try container.encodeNullable(medicineBox, forKey: .key("medicineBox"))
        try container.encodeNullable(prescription, forKey: .key("prescription"))
        try container.encode(drugName, forKey: .key("drugName"))
        try container.encode(dosePerTime, forKey: .key("dosePerTime"))
        try container.encodeNullable(doseValue, forKey: .key("doseValue"))
        try container.encode(doseUnit, forKey: .key("doseUnit"))
        try container.encode(frequencyType, forKey: .key("frequencyType"))
        try container.encodeNullable(everyNDays, forKey: .key("everyNDays"))
        try container.encode(weeklyWeekdays, forKey: .key("weeklyWeekdays"))
        try container.encode(frequencyText, forKey: .key("frequencyText"))
        try container.encode(reminderTimes, forKey: .key("reminderTimes"))
        try container.encode(startDate, forKey: .key("startDate"))
        try container.encodeNullable(endDate, forKey: .key("endDate"))
        try container.encode(instructions, forKey: .key("instructions"))
        try container.encode(reminderEnabled, forKey: .key("reminderEnabled"))
        try container.encode(status, forKey: .key("status"))
        try container.encode(extra, forKey: .key("extra"))
    }
}

private enum MedicationPlanFormError: LocalizedError {
    case invalidReminderTimes(String)

    var errorDescription: String? {
        switch self {
        case .invalidReminderTimes(let message):
            return message
        }
    }
}

private struct MedicationPrescriptionCard<Destination: View>: View {
    let prescription: SparkMedicalSyncAPI.RemotePrescription?
    let plans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    let medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox]
    let recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]]
    let fileTransferService: FileTransferService
    @ViewBuilder let planDestination: (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Destination

    private var title: String {
        prescription?.institutionName.nilIfBlank ?? L10n.text("home.medical.list.medications.prescription_batch", fallback: "处方批次")
    }

    private var subtitleItems: [String] {
        [
            prescription?.prescriberName.nilIfBlank.map {
                String(format: L10n.text("home.medical.list.medications.prescriber_format", fallback: "医生：%@"), locale: .current, $0)
            },
            prescription?.prescriptionNo?.nilIfBlank.map {
                String(format: L10n.text("home.medical.list.medications.prescription_no_format", fallback: "处方号：%@"), locale: .current, $0)
            },
            prescriptionDateText
        ].compactMap { $0 }
    }

    private var prescriptionDateText: String? {
        guard let date = prescription?.prescribedAt else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let diagnosis = prescription?.diagnosis.nilIfBlank {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("common.diagnosis"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .systemBlue))
                    Text(diagnosis)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color(uiColor: .systemBlue).opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(uiColor: .systemBlue).opacity(0.18), lineWidth: 1)
                )
            }

            Divider()

            HStack(spacing: 8) {
                Text(String(format: L10n.text("home.medical.list.medications.plan_count_format", fallback: "用药（%d种）"), locale: .current, plans.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let status = prescription?.status.nilIfBlank {
                    Text(prescriptionStatusText(status))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .systemPurple))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .systemPurple).opacity(0.12), in: Capsule())
                }
            }

            if plans.isEmpty {
                Text(L10n.text("home.medical.list.medications.empty.linked_plans", fallback: "暂无关联用药计划"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 8) {
                    ForEach(plans, id: \.id) { plan in
                        MainNavigationLink {
                            planDestination(plan)
                        } label: {
                            MedicationPrescriptionPlanRow(
                                plan: plan,
                                medicineBox: plan.medicineBox.flatMap { medicineBoxesByID[$0] },
                                records: recordsByPlanID[plan.id] ?? [],
                                fileTransferService: fileTransferService
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .systemPurple).opacity(0.14), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(uiColor: .systemPurple), Color(uiColor: .systemIndigo)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "doc.text.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if subtitleItems.isEmpty == false {
                    Text(subtitleItems.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)
        }
    }
}

private struct MedicationPrescriptionPlanRow: View {
    let plan: SparkMedicalSyncAPI.RemoteMedicationPlan
    let medicineBox: SparkMedicalSyncAPI.RemoteMedicineBox?
    let records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    let fileTransferService: FileTransferService

    private var takenCount: Int {
        records.filter { $0.status == "taken" }.count
    }

    private var imageAttachment: SparkMedicalSyncAPI.RemoteManagedFile? {
        if let boxAttachment = medicineBox?.attachments?.first(where: \.isMedicationImageLike) {
            return boxAttachment
        }
        return plan.attachments?.first(where: \.isMedicationImageLike)
    }

    private var subtitle: String {
        [
            plan.dosePerTime.nilIfBlank,
            plan.frequencyText.nilIfBlank,
            plan.reminderEnabled ? plan.reminderTimes.map(\.time).joined(separator: ", ").nilIfBlank : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MedicationImageGlyph(
                seed: plan.id,
                attachment: imageAttachment,
                fileTransferService: fileTransferService
            )
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.drugName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed", fallback: "未命名药品"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle.isEmpty ? L10n.text("home.medical.prescription.no_supplemental_info", fallback: "暂无补充信息") : subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(planStatusText(plan.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(plan.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(plan.status).opacity(0.12), in: Capsule())

                HStack(spacing: 4) {
                    Image(systemName: plan.reminderEnabled ? "bell.fill" : "bell.slash")
                    Text("\(takenCount)/\(records.count)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MedicationPlanCard: View {
    let plan: SparkMedicalSyncAPI.RemoteMedicationPlan
    let medicineBox: SparkMedicalSyncAPI.RemoteMedicineBox?
    let records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    let fileTransferService: FileTransferService

    private var takenCount: Int {
        records.filter { $0.status == "taken" }.count
    }

    private var imageAttachment: SparkMedicalSyncAPI.RemoteManagedFile? {
        if let boxAttachment = medicineBox?.attachments?.first(where: \.isMedicationImageLike) {
            return boxAttachment
        }
        return plan.attachments?.first(where: \.isMedicationImageLike)
    }

    private var subtitle: String {
        [
            plan.dosePerTime.nilIfBlank,
            plan.frequencyText.nilIfBlank,
            plan.reminderTimes.map(\.time).joined(separator: ", ").nilIfBlank
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MedicationImageGlyph(
                    seed: plan.id,
                    attachment: imageAttachment,
                    fileTransferService: fileTransferService
                )
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.drugName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed", fallback: "未命名药品"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle.isEmpty ? L10n.text("home.medical.prescription.no_supplemental_info", fallback: "暂无补充信息") : subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(planStatusText(plan.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(plan.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(plan.status).opacity(0.12), in: Capsule())
            }

            HStack(spacing: 12) {
                Label("\(takenCount)/\(records.count)", systemImage: "checkmark.circle")
                if let medicineBox {
                    Label(stockText(medicineBox), systemImage: "shippingbox")
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private func stockText(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
    guard let q = box.totalQuantity else { return L10n.text("home.medical.medication_plan.stock_not_filled", fallback: "总量未填") }
    return String(
        format: L10n.text("home.medical.medication_plan.stock_format", fallback: "总量 %@"),
        locale: .current,
        q.formatted(.number.precision(.fractionLength(0...2)))
    )
}

private func planStatusText(_ status: String) -> String {
    switch status {
    case "active":
        return L10n.text("home.medical.list.medications.status.active", fallback: "执行中")
    case "paused":
        return L10n.text("home.medical.list.medications.status.paused", fallback: "未开始")
    case "completed":
        return L10n.text("home.medical.list.medications.status.completed", fallback: "已完成")
    case "cancelled":
        return L10n.text("home.medical.list.medications.status.cancelled", fallback: "已取消")
    default:
        return status
    }
}

private func prescriptionStatusText(_ status: String) -> String {
    if PrescriptionLifecycleStatus.allRawValues.contains(status) {
        return PrescriptionLifecycleStatus.displayLabel(for: status)
    }
    return status
}

private func recordStatusText(_ status: String) -> String {
    switch status {
    case "scheduled":
        return L10n.text("home.medical.medication_plan.record.status.scheduled", fallback: "待服药")
    case "taken":
        return L10n.text("home.medical.medication_plan.record.status.taken", fallback: "已服药")
    case "skipped":
        return L10n.text("home.medical.medication_plan.record.status.skipped", fallback: "已漏服")
    case "snoozed":
        return L10n.text("home.medical.medication_plan.record.status.snoozed", fallback: "稍后提醒")
    default:
        return status
    }
}

private func statusColor(_ status: String) -> Color {
    switch status {
    case "active":
        return Color(uiColor: .systemBlue)
    case "paused":
        return Color(uiColor: .systemOrange)
    case "completed":
        return Color(uiColor: .systemGreen)
    case "cancelled":
        return Color(uiColor: .systemGray)
    default:
        return Color(uiColor: .secondaryLabel)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

#Preview("Medication Plans") {
    CompatibleNavigationContainer {
        MedicationsListPage(
            completeData: nil,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            medicalQueryAPI: AppContainer.preview.backend.medicalQuery,
            fileTransferService: AppContainer.preview.fileTransferService,
            memberContextStore: AppContainer.preview.memberContextStore,
            medicalDocumentUploadViewModel: AppContainer.preview.makeMedicalDocumentUploadViewModel(),
            aiSettingsViewModel: AppContainer.preview.makeAISettingsViewModel(ownerAccountID: 1),
            notificationClient: AppContainer.preview.notificationClient,
            logger: AppContainer.preview.logger
        )
    }
}
