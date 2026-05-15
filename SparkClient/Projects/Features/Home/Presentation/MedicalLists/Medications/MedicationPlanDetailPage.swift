import SwiftUI

struct MedicationPlanDetailPage: View {
    let plan: SparkMedicalSyncAPI.RemoteMedicationPlan
    let records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    let memberID: Int?
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    @ObservedObject var memberContextStore: MemberContextStore
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let notificationClient: any NotificationClient
    let onSaved: (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void
    let onDeleted: (Int) -> Void
    let onMedicineBoxSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    var onMedicineBoxDeleted: ((Int) -> Void)?
    var onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)?
    var onMedicalCaseDeleted: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var currentPlan: SparkMedicalSyncAPI.RemoteMedicationPlan
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var alertMessage: String?

    init(
        plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        memberID: Int?,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        memberContextStore: MemberContextStore,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        onSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void,
        onDeleted: @escaping (Int) -> Void,
        onMedicineBoxSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onMedicineBoxDeleted: ((Int) -> Void)? = nil,
        onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)? = nil,
        onMedicalCaseDeleted: ((Int) -> Void)? = nil
    ) {
        self.plan = plan
        self.records = records
        self.memberID = memberID
        self.completeData = completeData
        self.memberContextStore = memberContextStore
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.onMedicineBoxSaved = onMedicineBoxSaved
        self.onMedicineBoxDeleted = onMedicineBoxDeleted
        self.onMedicalCaseUpdated = onMedicalCaseUpdated
        self.onMedicalCaseDeleted = onMedicalCaseDeleted
        _currentPlan = State(initialValue: plan)
        _medicineBoxes = State(initialValue: medicineBoxes)
    }

    private var sortedRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord] {
        records.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var medicineBox: SparkMedicalSyncAPI.RemoteMedicineBox? {
        currentPlan.medicineBox.flatMap { id in
            medicineBoxes.first(where: { $0.id == id })
        }
    }

    var body: some View {
        List {
         
            if let medicineBox {
                Section("关联药品") {
                    NavigationLink {
                        MedicineBoxDetailPage(
                            box: medicineBox,
                            typeOptions: MedicineBoxTypeCatalog.options(in: medicineBoxes),
                            specOptionBoxes: medicineBoxes,
                            workflowAPI: workflowAPI,
                            fileTransferService: fileTransferService,
                            onSaved: handleMedicineBoxSaved,
                            onDeleted: handleMedicineBoxDeleted
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox.fill")
                                .font(.headline)
                                .foregroundStyle(Color(uiColor: .systemPurple))
                                .frame(width: 36, height: 36)
                                .background(Color(uiColor: .systemPurple).opacity(0.12), in: Circle())
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(medicationPlanDetailLinkedBoxTitle(medicineBox))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(medicationPlanDetailLinkedBoxSubtitle(medicineBox))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
             
            }else if currentPlan.medicineBox != nil {
                MedicationPlanDetailInfoRow(title: "药箱药品", value: "信息暂不可用，请同步药箱列表后重试")
            }
            
            Section("服药计划") {
                MedicationPlanDetailInfoRow(title: "药品", value: currentPlan.drugName)
                MedicationPlanDetailInfoRow(title: "剂量", value: currentPlan.dosePerTime)
                MedicationPlanDetailInfoRow(title: "频次", value: currentPlan.frequencyText)
                MedicationPlanDetailInfoRow(title: "提醒", value: currentPlan.reminderTimes.map(\.time).joined(separator: ", "))
                MedicationPlanDetailInfoRow(title: "状态", value: medicationPlanDetailStatusLabel(currentPlan.status))
                if currentPlan.instructions.isEmpty == false {
                    MedicationPlanDetailInfoRow(title: "说明", value: currentPlan.instructions)
                }
                
                MedicalResourceMedicalCaseLinkSection(
                    memberID: currentPlan.member,
                    medicalCaseID: currentPlan.medicalCase,
                    resourceKind: .medicationPlans,
                    resourceID: currentPlan.id,
                    patchField: .medicalCase,
                    workflowAPI: workflowAPI,
                    fileTransferService: fileTransferService,
                    completeData: completeData,
                    memberContextStore: memberContextStore,
                    notificationClient: notificationClient,
                    linkedTitle: L10n.text("home.medical.list.medications.linked_case.title", fallback: "已关联病例"),
                    linkedSubtitle: L10n.text("home.medical.list.medications.linked_case.subtitle", fallback: "点击查看病历详情与时间线"),
                    unlinkedTitle: L10n.text("home.medical.list.medications.unlinked_case.title", fallback: "关联病例"),
                    unlinkedSubtitle: L10n.text("home.medical.list.medications.unlinked_case.subtitle", fallback: "未关联，点击选择要归档的病历"),
                    onResourceUpdated: { (updated: SparkMedicalSyncAPI.RemoteMedicationPlan) in
                        currentPlan = updated
                        onSaved(updated)
                    },
                    onMedicalCaseUpdated: onMedicalCaseUpdated,
                    onMedicalCaseDeleted: onMedicalCaseDeleted
                )
            }
            
            if let attachments = currentPlan.attachments, attachments.isEmpty == false {
                Section("附件") {
                    MedicalAttachmentGridPreview(
                        attachments: attachments,
                        fileTransferService: fileTransferService
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            Section("服药记录") {
                if sortedRecords.isEmpty {
                    Text("暂无服药记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedRecords, id: \.id) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(record.scheduledAt.formatted(date: .omitted, time: .shortened))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(medicationPlanDetailRecordStatusLabel(record.status))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(record.status == "taken" ? Color(uiColor: .systemGreen) : Color(uiColor: .secondaryLabel))
                            }
                            Text("计划剂量 \(record.plannedDose)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let takenAt = record.takenAt {
                                Text("实际时间 \(takenAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if record.actualDose.isEmpty == false {
                                Text("实际剂量 \(record.actualDose)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(currentPlan.drugName.nilIfBlank ?? "服药计划")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .disabled(memberID == nil)

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let memberID {
                MedicationPlanFormView(
                    mode: .serverEdit(existing: currentPlan),
                    memberID: memberID,
                    medicineBoxes: medicineBoxes,
                    workflowAPI: workflowAPI,
                    fileTransferService: fileTransferService,
                    notificationClient: notificationClient,
                    onMedicineBoxSaved: handleMedicineBoxSaved,
                    onServerSaved: { saved in
                        currentPlan = saved
                        onSaved(saved)
                        showingEditSheet = false
                    }
                )
            } else {
                Text("请先选择成员")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("确认删除", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await deleteCurrentPlan() }
            }
        } message: {
            Text("删除后该服药计划及关联记录将不再显示。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onChange(of: plan) { newValue in
            currentPlan = newValue
        }
    }

    private func handleMedicineBoxSaved(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
            medicineBoxes[index] = box
        } else {
            medicineBoxes.insert(box, at: 0)
        }
        onMedicineBoxSaved(box)
    }

    private func handleMedicineBoxDeleted(_ id: Int) {
        medicineBoxes.removeAll { $0.id == id }
        onMedicineBoxDeleted?(id)
    }

    @MainActor
    private func deleteCurrentPlan() async {
        guard isDeleting == false else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await workflowAPI.delete(kind: .medicationPlans, id: currentPlan.id)
            onDeleted(currentPlan.id)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct MedicationPlanDetailInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.isEmpty ? "未填写" : value)
                .multilineTextAlignment(.trailing)
        }
    }
}

private func medicationPlanDetailStockText(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
    guard let q = box.totalQuantity else { return "总量未填" }
    return "总量 \(q.formatted(.number.precision(.fractionLength(0...2))))"
}

private func medicationPlanDetailLinkedBoxTitle(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
    box.medicineName.nilIfBlank ?? "未命名药品"
}

private func medicationPlanDetailLinkedBoxSubtitle(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
    let detail = [box.strength.nilIfBlank, box.dosageForm.nilIfBlank, medicationPlanDetailStockText(box)]
        .compactMap { $0 }
        .joined(separator: " · ")
    return detail.isEmpty ? "已关联药箱药品" : detail
}

private func medicationPlanDetailStatusLabel(_ status: String) -> String {
    switch status {
    case "active":
        return "执行中"
    case "paused":
        return "未开始"
    case "completed":
        return "已完成"
    case "cancelled":
        return "已取消"
    default:
        return status
    }
}

private func medicationPlanDetailRecordStatusLabel(_ status: String) -> String {
    switch status {
    case "scheduled":
        return "待服药"
    case "taken":
        return "已服药"
    case "skipped":
        return "已漏服"
    case "snoozed":
        return "稍后提醒"
    default:
        return status
    }
}
