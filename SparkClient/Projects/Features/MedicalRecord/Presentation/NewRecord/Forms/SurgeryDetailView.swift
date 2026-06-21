import SwiftUI

struct SurgeryDetailView: View {
    let memberID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let onUpdated: (SparkMedicalSyncAPI.SurgeryMutationResponse) -> Void
    let onDeleted: (Int, SparkMedicalSyncAPI.SurgeryMutationResponse) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentSurgery: SparkMedicalSyncAPI.RemoteSurgery
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var alertMessage: String?
    @State private var isDeleting = false

    init(
        surgery: SparkMedicalSyncAPI.RemoteSurgery,
        memberID: Int,
        workflowAPI: SparkMedicalWorkflowAPI,
        onUpdated: @escaping (SparkMedicalSyncAPI.SurgeryMutationResponse) -> Void,
        onDeleted: @escaping (Int, SparkMedicalSyncAPI.SurgeryMutationResponse) -> Void
    ) {
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        _currentSurgery = State(initialValue: surgery)
    }

    var body: some View {
        List {
            Section {
                Text(currentSurgery.procedureName.nilIfBlank ?? "未命名手术")
                    .font(.title3.weight(.semibold))
            }

            Section("手术信息") {
                SurgeryDetailRow(title: "手术时间", value: SurgeryFormSupport.performedAtText(for: currentSurgery))
                SurgeryDetailRow(title: "手术部位", value: currentSurgery.site)
                SurgeryDetailRow(title: "主治医生", value: currentSurgery.surgeon)
                SurgeryDetailRow(title: "麻醉方式", value: currentSurgery.anesthesiaType)
                SurgeryDetailRow(title: "切口等级", value: currentSurgery.incisionLevel)
                SurgeryDetailRow(title: "ASA分级", value: currentSurgery.asaClass)
                SurgeryDetailRow(title: "恢复状态", value: SurgeryFormSupport.recoveryStatus(for: currentSurgery))
                SurgeryDetailRow(title: "来源", value: SurgeryFormSupport.sourceLabel(for: currentSurgery))
                SurgeryDetailRow(title: "关联病例", value: SurgeryFormSupport.medicalCaseLabel(for: currentSurgery))
            }

            if currentSurgery.notes.nilIfBlank != nil || SurgeryFormSupport.hospitalName(for: currentSurgery).isEmpty == false {
                Section("备注") {
                    if SurgeryFormSupport.hospitalName(for: currentSurgery).isEmpty == false {
                        Text("主治医院：\(SurgeryFormSupport.hospitalName(for: currentSurgery))")
                    }
                    if let notes = currentSurgery.notes.nilIfBlank {
                        Text(notes)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("删除手术")
                        }
                        Spacer()
                    }
                }
                .disabled(isDeleting)
            }
        }
        .navigationTitle("手术详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("编辑") {
                    showingEditSheet = true
                }
                .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            CompatibleNavigationContainer {
                SurgeryFormView(
                    mode: .serverEdit(existing: currentSurgery),
                    submissionService: MedicalRecordFormSubmissionService(workflowAPI: workflowAPI),
                    memberID: memberID,
                    onMutation: { response in
                        if let updated = response.surgery {
                            currentSurgery = updated
                        }
                        onUpdated(response)
                    }
                )
            }
        }
        .alert("确认删除手术记录？", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await deleteCurrentSurgery() }
            }
        } message: {
            Text("删除后，该手术记录将不再用于成员医疗画像、AI体检建议和风险评估。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    @MainActor
    private func deleteCurrentSurgery() async {
        guard isDeleting == false else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let response = try await MedicalRecordFormSubmissionService(workflowAPI: workflowAPI)
                .submitSurgeryDelete(id: currentSurgery.id)
            onDeleted(currentSurgery.id, response)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct SurgeryDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.isEmpty ? "未填写" : value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
        }
    }
}
