import SwiftUI

/// 成员档案-长期用药分步填写页面
struct MemberMedicalLongTermMedicationStepView: View {
    /// 用药模块页面视图模型
    @ObservedObject var viewModel: MemberMedicalSetupViewModel
    /// 是否存在长期用药状态：none无 / have有
    @Binding var status: MedicalGuideDisclosureStatus

    /// 成员完整医疗档案数据
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    /// 医疗查询接口实例
    let medicalQueryAPI: SparkMedicalQueryAPI
    /// 文件上传/传输服务
    let fileTransferService: FileTransferService
    /// 当前家庭成员上下文存储
    @ObservedObject var memberContextStore: MemberContextStore
    /// 病历上传视图模型
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    /// AI设置视图模型（病历OCR识别使用）
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    /// 系统通知推送客户端
    let notificationClient: any NotificationClient
    /// 首页全局依赖集合
    let homeDependencies: HomeFeatureDependencies

    // 本地缓存状态
    /// 药盒容器列表
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] = []
    /// 处方单列表
    @State private var prescriptions: [SparkMedicalSyncAPI.RemotePrescription] = []
    /// 今日服药执行记录
    @State private var todayMedicationRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord] = []
    /// 档案数据加载标记
    @State private var isLoadingArchive = false
    /// 打开病历上传弹窗标记
    @State private var showingUploadSheet = false
    /// 新增/编辑用药表单弹窗目标枚举
    @State private var sheetDestination: MedicationPlanSheetDestination?

    /// 当前编辑成员ID
    private var memberID: Int {
        viewModel.member?.id ?? 0
    }

    /// 医疗工作流接口，由VM持有
    private var workflowAPI: SparkMedicalWorkflowAPI {
        viewModel.medicalWorkflowAPI
    }

    /// 药盒ID映射字典，快速通过ID查询药盒信息
    private var medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox] {
        Dictionary(uniqueKeysWithValues: medicineBoxes.map { ($0.id, $0) })
    }

    /// 用药计划ID -> 当日服药记录分组字典
    private var recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]] {
        Dictionary(grouping: todayMedicationRecords, by: \.plan)
    }

    /// 合并所有用药数据并按规则排序后的展示条目（独立用药计划 + 处方用药）
    private var sortedItems: [MedicalMedicationListItem] {
        MedicalMedicationListBuilder.sortedItems(
            medicationPlans: viewModel.memberMedicationPlans,
            prescriptions: prescriptions
        )
    }

    /// 筛选独立手动录入用药计划条目
    private var standaloneItems: [MedicalMedicationListItem] {
        sortedItems.filter {
            if case .standalonePlan = $0 { return true }
            return false
        }
    }

    /// 筛选处方单关联用药条目
    private var prescriptionItems: [MedicalMedicationListItem] {
        sortedItems.filter {
            if case .prescription = $0 { return true }
            return false
        }
    }

    /// 全局加载状态：接口加载 / 档案数据加载任一为true则显示加载动画
    private var isLoading: Bool {
        viewModel.isLoadingMemberMedications || isLoadingArchive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 第一步：有无长期用药选择卡片
            medicationScreeningCard

            // 选择「无长期用药」展示提示文案
            if status == .none {
                friendlyTipRow
            }

            // 选择「有长期用药」展示用药列表与新增按钮
            if status == .have {
                // 加载中且无数据时展示进度条
                if isLoading && sortedItems.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    // 用药档案列表区域
                    medicationArchiveSection
                    // 拍照识别处方 + 手动新增用药双按钮
                    addActionButtons
                }
            }
        }
        // 页面出现/切换成员ID时，重新拉取全部用药档案
        .task(id: memberID) {
            await loadMedicationArchive()
        }
        // 上传病历弹窗：选择图片/文件后回调OCR识别
        .sheet(isPresented: $showingUploadSheet) {
            MedicalAttachmentUploadListSheet(documentKind: .medicationPlan, onConfirm: startMedicationPlanRecognition)
        }
        // 新增/编辑用药分步表单弹窗
        .sheet(item: $sheetDestination) { destination in
            medicationPlanSheetContent(for: destination)
        }
        // 病历识别全屏页面
//        .fullScreenCover(isPresented: $medicalDocumentUploadViewModel.isUploadPresented) {
//            CompatibleNavigationContainer {
//                MedicalDocumentUploadHostView(
//                    viewModel: medicalDocumentUploadViewModel,
//                    aiSettingsViewModel: aiSettingsViewModel
//                )
//            }
//        }
        // OCR识别保存成功后刷新用药列表
        .onChange(of: medicalDocumentUploadViewModel.saveSucceededRevision) { _ in
            Task { await refreshAfterMedicalUploadSave() }
        }
        // 切换有无用药状态逻辑
        .onChange(of: status) { newValue in
            if newValue == .none {
                // 切换为无用药，关闭弹窗、清空编辑页面
                sheetDestination = nil
                showingUploadSheet = false
            } else if newValue == .have, sortedItems.isEmpty {
                // 切换为有用药且暂无数据，主动加载档案
                Task { await loadMedicationArchive() }
            }
        }
    }

    // MARK: 子视图拆分
    /// 有无长期用药单选选择卡片
    private var medicationScreeningCard: some View {
        MemberSetupSection(title: L10n.text("member.setup.medical.medication.3d3075")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("member.setup.medical.medication.5e6c3f"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    screeningChoice(
                        title: L10n.text("member.setup.medical.medication.4c60e8"),
                        isSelected: status == .none,
                        action: { status = .none }
                    )
                    screeningChoice(
                        title: L10n.text("member.setup.medical.medication.24f228"),
                        isSelected: status == .have,
                        action: { status = .have }
                    )
                }
            }
        }
    }

    /// 选择无用药时的灯泡提示文案
    private var friendlyTipRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(L10n.text("member.setup.medical.medication.d23003"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 用药档案列表区域：独立用药计划 + 处方用药分组展示
    @ViewBuilder
    private var medicationArchiveSection: some View {
        if sortedItems.isEmpty {
            // 暂无用药数据占位提示
            MemberSetupSection(title: L10n.text("member.setup.medical.medication.9be2aa")) {
                Text(L10n.text("member.setup.medical.medication.b85a51"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            // 独立手动录入用药分组
            if standaloneItems.isEmpty == false {
                MemberSetupSection(title: L10n.text("member.setup.medical.medication.9be2aa")) {
                    VStack(spacing: 10) {
                        ForEach(standaloneItems) { item in
                            if case .standalonePlan(let plan) = item {
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
                            }
                        }
                    }
                }
            }

            // 处方单关联用药分组
            if prescriptionItems.isEmpty == false {
                MemberSetupSection(title: L10n.text("member.setup.medical.medication.4775f3")) {
                    VStack(spacing: 10) {
                        ForEach(prescriptionItems) { item in
                            if case .prescription(_, let prescription, let plans) = item {
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
                                        onPlanSaved: handlePlanSavedLocally,
                                        onPlanDeleted: handlePlanDeletedLocally,
                                        onPlanMutation: handleMedicationMutation
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
                            }
                        }
                    }
                }
            }
        }
    }

    /// 底部操作按钮：拍照识别处方 / 手动新增用药
    private var addActionButtons: some View {
        VStack(spacing: 12) {
            // 拍照/相册识别处方
            Button {
                showingUploadSheet = true
            } label: {
                Label(L10n.text("member.setup.medical.medication.e451a1"), systemImage: "camera.viewfinder")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            // 手动录入用药计划
            Button {
                sheetDestination = .create
            } label: {
                Label(L10n.text("member.setup.medical.medication.63edd6"), systemImage: "pencil.line")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    /// 用药新增/编辑分步表单弹窗内容
    @ViewBuilder
    private func medicationPlanSheetContent(for destination: MedicationPlanSheetDestination) -> some View {
        MedicationPlanStepperView(
            mode: destination.planMode,
            memberID: memberID,
            medicineBoxes: medicineBoxes,
            workflowAPI: workflowAPI,
            fileTransferService: fileTransferService,
            notificationClient: notificationClient,
            onMedicineBoxSaved: upsertMedicineBox,
            onServerSaved: handlePlanSavedLocally,
            onMutation: handleMedicationMutation,
            homeDependencies: homeDependencies,
            memberContextStore: memberContextStore
        )
    }

    /// 独立用药计划详情页面
    private func planDetailPage(for plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> some View {
        MedicationPlanDetailPage(
            plan: plan,
            medicineBoxes: medicineBoxes,
            memberID: memberID,
            completeData: completeData,
            memberContextStore: memberContextStore,
            workflowAPI: workflowAPI,
            fileTransferService: fileTransferService,
            notificationClient: notificationClient,
            homeDependencies: homeDependencies,
            onSaved: handlePlanSavedLocally,
            onDeleted: handlePlanDeletedLocally,
            onMedicineBoxSaved: upsertMedicineBox,
            onMedicineBoxDeleted: removeMedicineBox,
            onMutation: handleMedicationMutation
        )
    }

    /// 有无用药单选胶囊按钮组件
    private func screeningChoice(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 业务逻辑方法
    /// 并发拉取全部用药相关档案：用药计划、处方、药盒、今日服药记录
    @MainActor
    private func loadMedicationArchive() async {
        guard memberID > 0 else { return }
        isLoadingArchive = true
        defer { isLoadingArchive = false }

        do {
            // 并发并行请求多个接口提升加载速度
            async let plansTask = viewModel.refreshMemberMedicationPlansIfNeeded(force: true)
            async let prescriptionsTask = medicalQueryAPI.listPrescriptions(memberID: memberID)
            async let boxesTask = medicalQueryAPI.listMedicineBoxes(memberID: memberID)
            _ = await plansTask
            let (prescriptionRows, boxes) = try await (prescriptionsTask, boxesTask)
            prescriptions = prescriptionRows
            medicineBoxes = boxes

            // 计算今日时间区间，查询今日服药执行记录
            let startOfDay = Calendar.current.startOfDay(for: Date())
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            todayMedicationRecords = try await medicalQueryAPI.listMedicationRecords(
                memberID: memberID,
                scheduledRange: MedicationRecordScheduledRange(
                    scheduledFrom: startOfDay,
                    scheduledToExclusive: endOfDay
                )
            )
        } catch {
            // 请求失败弹出系统通知提示错误
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "medical.setup.medication.load")
        }
    }

    /// OCR上传识别保存成功后，重新刷新全部用药数据
    @MainActor
    private func refreshAfterMedicalUploadSave() async {
        await loadMedicationArchive()
    }

    /// 选择病历文件后，启动用药处方OCR识别流程
    @MainActor
    private func startMedicationPlanRecognition(files: [MedicalUploadLocalFile]) {
        showingUploadSheet = false
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .medicationPlan, member: viewModel.member)
    }

    /// 用药新增/编辑/删除后统一回调，同步数据并关闭弹窗、同步提醒
    @MainActor
    private func handleMedicationMutation(_ response: SparkMedicalSyncAPI.MedicationMutationResponse) {
        viewModel.applyMedicationMutation(response)
        sheetDestination = nil
        syncMedicationReminderAfterPlanChange()
    }

    /// 新增/编辑用药计划成功，更新本地缓存列表
    @MainActor
    private func handlePlanSavedLocally(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) {
        viewModel.ingestSavedMedicationPlans([plan])
    }

    /// 删除用药计划，本地移除对应条目并同步提醒
    @MainActor
    private func handlePlanDeletedLocally(id: Int) {
        viewModel.memberMedicationPlans.removeAll { $0.id == id }
        syncMedicationReminderAfterPlanChange()
    }

    /// 新增/编辑处方，更新本地处方缓存
    @MainActor
    private func upsertPrescription(_ prescription: SparkMedicalSyncAPI.RemotePrescription) {
        if let index = prescriptions.firstIndex(where: { $0.id == prescription.id }) {
            prescriptions[index] = prescription
        } else {
            prescriptions.insert(prescription, at: 0)
        }
    }

    /// 删除处方，本地移除缓存
    @MainActor
    private func removePrescription(id: Int) {
        prescriptions.removeAll { $0.id == id }
    }

    /// 新增/编辑药盒，更新本地缓存
    @MainActor
    private func upsertMedicineBox(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
            medicineBoxes[index] = box
        } else {
            medicineBoxes.insert(box, at: 0)
        }
    }

    /// 删除药盒，本地移除缓存
    @MainActor
    private func removeMedicineBox(id: Int) {
        medicineBoxes.removeAll { $0.id == id }
    }

    /// 用药计划发生增删改后，同步刷新本地服药提醒调度
    private func syncMedicationReminderAfterPlanChange() {
        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
        let coordinator = homeDependencies.medicationReminderSyncCoordinator
        coordinator.activate(accountID: session.accountID)
        coordinator.rebuildAfterPlanChanged(
            accountID: session.accountID,
            members: memberContextStore.context.members
        )
    }
}
