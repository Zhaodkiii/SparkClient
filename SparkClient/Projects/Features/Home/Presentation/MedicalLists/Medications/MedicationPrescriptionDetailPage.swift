import SwiftUI

/// 处方详情页面
/// 展示单张处方完整信息：头部基础信息、诊断、附件、关联用药方案；支持编辑、删除处方、解绑/同步病历、单条用药方案操作
struct MedicationPrescriptionDetailPage: View {
    @Environment(\.dismiss) private var dismiss

    let mode: MedicationPrescriptionDetailMode
    let memberID: Int?
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    @ObservedObject var memberContextStore: MemberContextStore
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let notificationClient: any NotificationClient

    let onPrescriptionSaved: (SparkMedicalSyncAPI.RemotePrescription) -> Void
    let onPrescriptionDeleted: (Int) -> Void
    let onPlanSaved: (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void
    let onPlanDeleted: (Int) -> Void
    var onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)?
    var onMedicalCaseDeleted: ((Int) -> Void)?

    var onLocalDraftPrescriptionUpdated: ((PrescriptionRecognitionDraft) -> Void)?
    var onLocalDraftPrescriptionDeleted: (() -> Void)?
    var onLocalDraftMedicationPlanSaved: ((Int, MedicationPlanRecognitionDraft) -> Void)?
    var onLocalDraftMedicationPlanDeleted: ((Int) -> Void)?
    var onLocalDraftMedicineBoxSaved: ((Int, MedicineBoxRecognitionDraft) -> Void)?
    var onLocalDraftMedicineBoxDeleted: ((Int) -> Void)?

    private let prescriptionIndex: Int

    @State private var currentPrescription: SparkMedicalSyncAPI.RemotePrescription?
    @State private var currentPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    @State private var medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]]
    @State private var sourceBatchDraft: PrescriptionRecognitionDraft?
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var deleteLinkedPlans = false
    @State private var isDeleting = false
    @State private var alertMessage: String?

    init(
        mode: MedicationPrescriptionDetailMode = .server,
        prescription: SparkMedicalSyncAPI.RemotePrescription?,
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]],
        memberID: Int?,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        memberContextStore: MemberContextStore,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        prescriptionIndex: Int = 0,
        sourceBatchDraft: PrescriptionRecognitionDraft? = nil,
        onPrescriptionSaved: @escaping (SparkMedicalSyncAPI.RemotePrescription) -> Void,
        onPrescriptionDeleted: @escaping (Int) -> Void,
        onPlanSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void,
        onPlanDeleted: @escaping (Int) -> Void,
        onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)? = nil,
        onMedicalCaseDeleted: ((Int) -> Void)? = nil,
        onLocalDraftPrescriptionUpdated: ((PrescriptionRecognitionDraft) -> Void)? = nil,
        onLocalDraftPrescriptionDeleted: (() -> Void)? = nil,
        onLocalDraftMedicationPlanSaved: ((Int, MedicationPlanRecognitionDraft) -> Void)? = nil,
        onLocalDraftMedicationPlanDeleted: ((Int) -> Void)? = nil,
        onLocalDraftMedicineBoxSaved: ((Int, MedicineBoxRecognitionDraft) -> Void)? = nil,
        onLocalDraftMedicineBoxDeleted: ((Int) -> Void)? = nil
    ) {
        self.mode = mode
        _currentPrescription = State(initialValue: prescription)
        _currentPlans = State(initialValue: plans)
        _medicineBoxesByID = State(initialValue: Dictionary(uniqueKeysWithValues: medicineBoxes.map { ($0.id, $0) }))
        _recordsByPlanID = State(initialValue: recordsByPlanID)
        _sourceBatchDraft = State(initialValue: sourceBatchDraft)

        self.memberID = memberID
        self.completeData = completeData
        self.memberContextStore = memberContextStore
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
        self.onPrescriptionSaved = onPrescriptionSaved
        self.onPrescriptionDeleted = onPrescriptionDeleted
        self.onPlanSaved = onPlanSaved
        self.onPlanDeleted = onPlanDeleted
        self.onMedicalCaseUpdated = onMedicalCaseUpdated
        self.onMedicalCaseDeleted = onMedicalCaseDeleted
        self.onLocalDraftPrescriptionUpdated = onLocalDraftPrescriptionUpdated
        self.onLocalDraftPrescriptionDeleted = onLocalDraftPrescriptionDeleted
        self.onLocalDraftMedicationPlanSaved = onLocalDraftMedicationPlanSaved
        self.onLocalDraftMedicationPlanDeleted = onLocalDraftMedicationPlanDeleted
        self.onLocalDraftMedicineBoxSaved = onLocalDraftMedicineBoxSaved
        self.onLocalDraftMedicineBoxDeleted = onLocalDraftMedicineBoxDeleted
        self.prescriptionIndex = prescriptionIndex
    }

    // MARK: 导航栏标题计算属性
    private var title: String {
        // 优先使用医院名称，无则使用默认多语言标题
        currentPrescription?.institutionName.nilIfBlank ?? L10n.text("home.medical.prescription.detail.title")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard          // 头部信息卡片
                diagnosisCard       // 诊断内容卡片
                attachmentsSection  // 附件预览区域
                medicationSection   // 关联用药方案列表
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // 右上角更多操作菜单：编辑、删除
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // 编辑处方按钮
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label(L10n.text("common.edit"), systemImage: "pencil")
                    }
                    .disabled(memberID == nil || currentPrescription == nil)

                    // 删除处方按钮（危险操作）
                    Button(role: .destructive) {
                        deleteLinkedPlans = false
                        showingDeleteConfirm = true
                    } label: {
                        Label(L10n.text("common.delete"), systemImage: "trash")
                    }
                    .disabled(currentPrescription == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isDeleting)
            }
        }
        // 编辑处方弹窗
        .sheet(isPresented: $showingEditSheet) {
            if let currentPrescription {
                CompatibleNavigationContainer {
                    if mode == .localDraft {
                        MedicationPrescriptionEditPage(
                            mode: .localEdit(existing: currentSourceDraft(), onSubmit: { updated in
                                applyLocalPrescriptionDraft(updated)
                                showingEditSheet = false
                            }),
                            workflowAPI: workflowAPI,
                            fileTransferService: fileTransferService,
                            notificationClient: notificationClient
                        )
                    } else {
                        MedicationPrescriptionEditPage(
                            prescription: currentPrescription,
                            plans: currentPlans,
                            workflowAPI: workflowAPI,
                            fileTransferService: fileTransferService,
                            notificationClient: notificationClient,
                            onSaved: { saved in
                                self.currentPrescription = saved
                                onPrescriptionSaved(saved)
                            },
                            onPlanUnlinked: { plan in
                                currentPlans.removeAll { $0.id == plan.id }
                                onPlanSaved(plan)
                            }
                        )
                    }
                }
            }
        }
        // 删除确认弹窗
        .sheet(isPresented: $showingDeleteConfirm) {
            deleteConfirmSheet
        }
        // 接口异常全局提示弹窗
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: 病历绑定/解绑子组件
    /// 处方关联病历绑定、解绑模块
    private func prescriptionMedicalCaseLinkSection(prescription: SparkMedicalSyncAPI.RemotePrescription) -> some View {
        MedicalResourceMedicalCaseLinkSection(
            memberID: prescription.member,
            medicalCaseID: prescription.medicalCase,
            resourceKind: .prescriptions,
            resourceID: prescription.id,
            patchField: .medicalCase,
            workflowAPI: workflowAPI,
            fileTransferService: fileTransferService,
            completeData: completeData,
            memberContextStore: memberContextStore,
            notificationClient: notificationClient,
            linkedTitle: L10n.text("home.medical.list.medications.linked_case.title"),
            linkedSubtitle: L10n.text("home.medical.list.medications.linked_case.subtitle"),
            unlinkedTitle: L10n.text("home.medical.list.medications.unlinked_case.title"),
            unlinkedSubtitle: L10n.text("home.medical.list.medications.unlinked_case.subtitle"),
            onResourceUpdated: { (updated: SparkMedicalSyncAPI.RemotePrescription) in
                // 病历绑定变更后刷新本地处方并回调上层
                currentPrescription = updated
                onPrescriptionSaved(updated)
            },
            onMedicalCaseUpdated: onMedicalCaseUpdated,
            onMedicalCaseDeleted: onMedicalCaseDeleted
        )
    }

    // MARK: 头部信息卡片
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                // 渐变图标背景
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(uiColor: .systemPurple), Color(uiColor: .systemIndigo)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "doc.text.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 6) {
                    Text(currentPrescription?.institutionName.nilIfBlank ?? L10n.text("home.medical.prescription.batch_fallback_title"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
            }

            // 处方详情信息网格行
            detailGrid

            // 病历绑定模块（草稿模式隐藏，避免误调用服务端）
            if mode == .server, let prescription = currentPrescription {
                prescriptionMedicalCaseLinkSection(prescription: prescription)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: 头部副标题拼接（医师+处方号+开具日期）
    private var headerSubtitle: String {
        [
            currentPrescription?.prescriberName.nilIfBlank.map {
                String(format: L10n.text("home.medical.prescription.header.doctor_format"), $0)
            },
            currentPrescription?.prescriptionNo?.nilIfBlank.map {
                String(format: L10n.text("home.medical.prescription.header.rx_no_format"), $0)
            },
            currentPrescription?.prescribedAt.map { $0.formatted(date: .abbreviated, time: .omitted) }
        ].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: 详情多行信息列表
    private var detailGrid: some View {
        VStack(spacing: 10) {
            PrescriptionDetailInfoRow(
                title: L10n.text("home.medical.prescription.field.status"),
                value: currentPrescription?.status.nilIfBlank.map(prescriptionStatusText) ?? L10n.text("home.medical.medicine_box.not_filled")
            )
            PrescriptionDetailInfoRow(
                title: L10n.text("home.medical.prescription.field.institution"),
                value: currentPrescription?.institutionName.nilIfBlank ?? L10n.text("home.medical.medicine_box.not_filled")
            )
            PrescriptionDetailInfoRow(
                title: L10n.text("home.medical.prescription.field.prescriber"),
                value: currentPrescription?.prescriberName.nilIfBlank ?? L10n.text("home.medical.medicine_box.not_filled")
            )
            PrescriptionDetailInfoRow(
                title: L10n.text("home.medical.prescription.field.prescription_no"),
                value: currentPrescription?.prescriptionNo?.nilIfBlank ?? L10n.text("home.medical.medicine_box.not_filled")
            )
            PrescriptionDetailInfoRow(
                title: L10n.text("home.medical.prescription.field.prescribed_at"),
                value: currentPrescription?.prescribedAt.map { $0.formatted(date: .abbreviated, time: .omitted) }
                    ?? L10n.text("home.medical.medicine_box.not_filled")
            )
        }
    }

    // MARK: 附件预览区域
    @ViewBuilder
    private var attachmentsSection: some View {
        if let attachments = currentPrescription?.attachments, attachments.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.text("common.attachments"), systemImage: "paperclip")
                    .font(.headline)
                MedicalAttachmentGridPreview(
                    attachments: attachments,
                    fileTransferService: fileTransferService
                )
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: 诊断内容卡片
    @ViewBuilder
    private var diagnosisCard: some View {
        if let diagnosis = currentPrescription?.diagnosis.nilIfBlank {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.text("common.diagnosis"), systemImage: "stethoscope")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                Text(diagnosis)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Color(uiColor: .systemBlue).opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(uiColor: .systemBlue).opacity(0.16), lineWidth: 1)
            )
        }
    }

    // MARK: 关联用药方案列表区域
    private var medicationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("home.medical.prescription.linked_medications"), systemImage: "pills.fill")
                    .font(.headline)
                Spacer()
                Text(String(format: L10n.text("home.medical.prescription.linked_count"), currentPlans.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            // 无用药方案空提示
            if currentPlans.isEmpty {
                Text(L10n.text("home.medical.prescription.no_linked_plans"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(currentPlans.enumerated()), id: \.element.id) { pair in
                        let medicationIndex = pair.offset
                        let plan = pair.element
                        PrescriptionMedicationPlanSummaryRow(
                            plan: plan,
                            medicineBox: plan.medicineBox.flatMap { medicineBoxesByID[$0] },
                            records: mode == .localDraft ? [] : (recordsByPlanID[plan.id] ?? []),
                            fileTransferService: fileTransferService,
                            planDetailNavigation: PrescriptionMedicationPlanSummaryRow.PlanDetailNavigation(
                                mode: mode == .localDraft ? .localDraft : .server,
                                medicationIndex: medicationIndex,
                                sourcePlanDraft: sourceBatchDraft?.medicationPlans?[safe: medicationIndex],
                                medicineBoxes: Array(medicineBoxesByID.values),
                                memberID: memberID,
                                completeData: completeData,
                                memberContextStore: memberContextStore,
                                workflowAPI: workflowAPI,
                                notificationClient: notificationClient,
                                onPlanSaved: { updated in
                                    if let idx = currentPlans.firstIndex(where: { $0.id == updated.id }) {
                                        currentPlans[idx] = updated
                                    }
                                    onPlanSaved(updated)
                                },
                                onPlanDeleted: { id in
                                    currentPlans.removeAll { $0.id == id }
                                    onPlanDeleted(id)
                                },
                                onMedicineBoxSaved: { box in
                                    medicineBoxesByID[box.id] = box
                                },
                                onMedicineBoxDeleted: nil,
                                onLocalDraftPlanSaved: { updatedDraft in
                                    handleLocalDraftPlanSaved(medicationIndex: medicationIndex, updatedDraft: updatedDraft)
                                },
                                onLocalDraftPlanDeleted: {
                                    handleLocalDraftPlanDeleted(medicationIndex: medicationIndex)
                                },
                                onLocalDraftMedicineBoxSaved: { updatedBox in
                                    handleLocalDraftMedicineBoxSaved(medicationIndex: medicationIndex, updatedBox: updatedBox)
                                },
                                onLocalDraftMedicineBoxDeleted: {
                                    handleLocalDraftMedicineBoxDeleted(medicationIndex: medicationIndex)
                                }
                            )
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: 删除确认弹窗内容视图
    private var deleteConfirmSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("home.medical.prescription.delete.title"))
                .font(.title3.weight(.semibold))
            Text(mode == .localDraft
                ? L10n.text("home.medical.prescription.delete.message")
                : L10n.text("home.medical.prescription.delete.message"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if mode == .server {
                Toggle(L10n.text("home.medical.prescription.delete.linked_plans"), isOn: $deleteLinkedPlans)
                    .font(.subheadline.weight(.medium))
                    .toggleStyle(.switch)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                // 取消按钮
                Button(L10n.text("common.cancel")) {
                    showingDeleteConfirm = false
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                // 确认删除按钮，loading状态展示进度圈
                Button(role: .destructive) {
                    Task { await deleteCurrentPrescription() }
                } label: {
                    if isDeleting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(L10n.text("home.medical.medicine_box.delete.confirm_title"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDeleting)
            }
        }
        .padding(20)
    }

    // MARK: 执行处方删除异步逻辑
    @MainActor
    private func deleteCurrentPrescription() async {
        guard currentPrescription != nil, isDeleting == false else { return }

        if mode == .localDraft {
            onLocalDraftPrescriptionDeleted?()
            showingDeleteConfirm = false
            dismiss()
            return
        }

        guard let prescription = currentPrescription else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            if deleteLinkedPlans {
                for plan in currentPlans {
                    try await workflowAPI.delete(kind: .medicationPlans, id: plan.id)
                    onPlanDeleted(plan.id)
                }
            } else {
                for plan in currentPlans {
                    let updated = try await workflowAPI.update(
                        SparkMedicalSyncAPI.RemoteMedicationPlan.self,
                        kind: .medicationPlans,
                        id: plan.id,
                        body: MedicationPlanPrescriptionUpdatePayload(prescription: nil)
                    )
                    onPlanSaved(updated)
                }
            }

            try await workflowAPI.delete(kind: .prescriptions, id: prescription.id)
            onPrescriptionDeleted(prescription.id)
            showingDeleteConfirm = false
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
            notificationClient.error(
                error.localizedDescription,
                title: L10n.text("home.medical.prescription.delete.failed"),
                source: "home.prescription.delete"
            )
        }
    }

    private func currentSourceDraft() -> PrescriptionRecognitionDraft {
        if let sourceBatchDraft {
            return sourceBatchDraft
        }
        return PrescriptionRecognitionDraftMapper.prescriptionDraft(
            from: currentPrescription ?? SparkMedicalSyncAPI.RemotePrescription(
                id: 0,
                member: memberID ?? 0,
                medicalCase: nil,
                prescriberName: "",
                institutionName: "",
                prescribedAt: nil,
                diagnosis: "",
                prescriptionNo: nil,
                status: "active",
                extra: nil,
                attachments: nil,
                updatedAt: Date()
            ),
            plans: currentPlans,
            medicineBoxesByID: medicineBoxesByID,
            preserving: nil
        )
    }

    private func applyLocalPrescriptionDraft(_ updated: PrescriptionRecognitionDraft) {
        sourceBatchDraft = updated
        guard let memberID else { return }
        let prescriptionID = currentPrescription?.id
            ?? PrescriptionRecognitionDraftMapper.temporaryPrescriptionID(prescriptionIndex: prescriptionIndex)
        currentPrescription = updated.remotePrescription(memberID: memberID, id: prescriptionID)
        let boxes = PrescriptionRecognitionDraftMapper.remoteMedicineBoxes(
            from: updated,
            memberID: memberID,
            prescriptionIndex: prescriptionIndex
        )
        medicineBoxesByID = Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0) })
        currentPlans = PrescriptionRecognitionDraftMapper.remoteMedicationPlans(
            from: updated,
            memberID: memberID,
            prescriptionIndex: prescriptionIndex,
            medicineBoxes: boxes
        )
        onLocalDraftPrescriptionUpdated?(updated)
    }

    private func handleLocalDraftPlanSaved(medicationIndex: Int, updatedDraft: MedicationPlanRecognitionDraft) {
        guard currentPlans.indices.contains(medicationIndex), let memberID, let prescription = currentPrescription else { return }

        let boxID: Int?
        if PrescriptionRecognitionDraftMapper.isMedicineBoxUnlinked(updatedDraft) {
            boxID = nil
            if let oldBoxID = currentPlans[medicationIndex].medicineBox {
                medicineBoxesByID.removeValue(forKey: oldBoxID)
            }
        } else {
            boxID = currentPlans[medicationIndex].medicineBox
                ?? PrescriptionRecognitionDraftMapper.temporaryMedicineBoxID(
                    prescriptionIndex: prescriptionIndex,
                    medicationIndex: medicationIndex
                )
        }

        let updatedPlan = PrescriptionRecognitionDraftMapper.remoteMedicationPlan(
            from: updatedDraft,
            preserving: currentPlans[medicationIndex],
            medicineBoxID: boxID
        )
        currentPlans[medicationIndex] = updatedPlan

        if let boxID, !PrescriptionRecognitionDraftMapper.isMedicineBoxUnlinked(updatedDraft) {
            let remoteBox = updatedDraft.remoteMedicineBox(memberID: memberID, id: boxID)
            medicineBoxesByID[remoteBox.id] = remoteBox
        }

        var draft = currentSourceDraft()
        var plans = draft.medicationPlans ?? []
        if plans.indices.contains(medicationIndex) {
            plans[medicationIndex] = updatedDraft
            draft.medicationPlans = plans
            sourceBatchDraft = draft
        }
        onLocalDraftMedicationPlanSaved?(medicationIndex, updatedDraft)
    }

    private func handleLocalDraftPlanDeleted(medicationIndex: Int) {
        guard currentPlans.indices.contains(medicationIndex) else { return }
        let removedPlan = currentPlans.remove(at: medicationIndex)
        if let boxID = removedPlan.medicineBox {
            medicineBoxesByID.removeValue(forKey: boxID)
        }

        var draft = currentSourceDraft()
        var plans = draft.medicationPlans ?? []
        if plans.indices.contains(medicationIndex) {
            plans.remove(at: medicationIndex)
            draft.medicationPlans = plans
            sourceBatchDraft = draft
        }
        onLocalDraftMedicationPlanDeleted?(medicationIndex)
    }

    private func handleLocalDraftMedicineBoxSaved(medicationIndex: Int, updatedBox: MedicineBoxRecognitionDraft) {
        guard currentPlans.indices.contains(medicationIndex), let memberID else { return }
        let boxID = currentPlans[medicationIndex].medicineBox
            ?? PrescriptionRecognitionDraftMapper.temporaryMedicineBoxID(
                prescriptionIndex: prescriptionIndex,
                medicationIndex: medicationIndex
            )
        let remoteBox = updatedBox.remoteMedicineBox(memberID: memberID, id: boxID)
        medicineBoxesByID[remoteBox.id] = remoteBox
    }

    private func handleLocalDraftMedicineBoxDeleted(medicationIndex: Int) {
        guard currentPlans.indices.contains(medicationIndex) else { return }
        if let boxID = currentPlans[medicationIndex].medicineBox {
            medicineBoxesByID.removeValue(forKey: boxID)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: 详情页单行键值对信息行
private struct PrescriptionDetailInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: 处方状态码转本地化展示文案
private func prescriptionStatusText(_ status: String) -> String {
    switch status {
    case "active":
        return L10n.text("home.medical.prescription.status.active")
    case "draft":
        return L10n.text("home.medical.prescription.status.draft")
    case "paid":
        return L10n.text("home.medical.prescription.status.paid")
    case "dispensed":
        return L10n.text("home.medical.prescription.status.dispensed")
    case "completed":
        return L10n.text("home.medical.prescription.status.completed")
    case "cancelled":
        return L10n.text("home.medical.prescription.status.cancelled")
    default:
        return status
    }
}

// MARK: 用药方案解绑处方专用请求体
/// 用于PATCH接口，将用药方案的prescription字段置空（解绑处方）
struct MedicationPlanPrescriptionUpdatePayload: Encodable {
    let prescription: Int?

    // 自定义编码：字段存在则传ID，不存在显式传null
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodableKey.self)
        if let prescription {
            try container.encode(prescription, forKey: .key("prescription"))
        } else {
            try container.encodeNil(forKey: .key("prescription"))
        }
    }
}
