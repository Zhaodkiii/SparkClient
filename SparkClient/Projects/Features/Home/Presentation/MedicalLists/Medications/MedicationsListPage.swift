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
            MedicationPlanStepperView(
                mode: destination.formMode,
                memberID: memberID,
                medicineBoxes: medicineBoxes,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                notificationClient: notificationClient,
                onMedicineBoxSaved: upsertMedicineBox,
                onServerSaved: upsertMedicationPlanWithoutReminderPrompts,
                homeDependencies: homeDependencies,
                memberContextStore: memberContextStore
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
                                    homeDependencies: homeDependencies,
                                    onPrescriptionSaved: upsertPrescription,
                                    onPrescriptionDeleted: removePrescription,
                                    onPlanSaved: upsertMedicationPlanWithoutReminderPrompts,
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
            homeDependencies: homeDependencies,
            onSaved: upsertMedicationPlanWithoutReminderPrompts,
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
    /// 新增/编辑服药计划，更新本地列表并触发外部回调（列表页不展示提醒协同弹窗）
    private func upsertMedicationPlanWithoutReminderPrompts(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) {
        if let index = medicationPlans.firstIndex(where: { $0.id == plan.id }) {
            medicationPlans[index] = plan
        } else {
            medicationPlans.insert(plan, at: 0)
        }
        onMedicationPlansChanged?(medicationPlans)
        syncMedicationReminderAfterPlanChange()
        sheetDestination = nil
    }

    /// 删除指定ID服药计划
    private func removeMedicationPlan(id: Int) {
        medicationPlans.removeAll { $0.id == id }
        onMedicationPlansChanged?(medicationPlans)
        syncMedicationReminderAfterPlanChange()
    }

    /// 列表页仅静默重建本地通知，协同引导弹窗在计划详情页处理
    private func syncMedicationReminderAfterPlanChange() {
        guard let homeDependencies else { return }
        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
        let coordinator = homeDependencies.medicationReminderSyncCoordinator
        coordinator.activate(accountID: session.accountID)
        coordinator.rebuildAfterPlanChanged(
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

    var formMode: MedicationPlanStepperView.Mode {
        switch self {
        case .create:
            return .create
        case .serverEdit(let plan):
            return .serverEdit(existing: plan)
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
