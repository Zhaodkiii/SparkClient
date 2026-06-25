import SwiftUI

struct SymptomDetailView: View {
    let memberID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let onUpdated: (SparkMedicalSyncAPI.SymptomMutationResponse) -> Void
    let onDeleted: (Int, SparkMedicalSyncAPI.SymptomMutationResponse) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentSymptom: SparkMedicalSyncAPI.RemoteSymptom
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var alertMessage: String?
    @State private var isDeleting = false

    init(
        symptom: SparkMedicalSyncAPI.RemoteSymptom,
        memberID: Int,
        workflowAPI: SparkMedicalWorkflowAPI,
        onUpdated: @escaping (SparkMedicalSyncAPI.SymptomMutationResponse) -> Void,
        onDeleted: @escaping (Int, SparkMedicalSyncAPI.SymptomMutationResponse) -> Void
    ) {
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        _currentSymptom = State(initialValue: symptom)
    }

    var body: some View {
        List {
            Section {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Section("症状信息") {
                SymptomDetailRow(title: "严重程度", value: severityText)
                SymptomDetailRow(title: "持续时间", value: SymptomFormSupport.durationText(for: currentSymptom))
                SymptomDetailRow(title: "开始时间", value: SymptomFormSupport.startedAtText(for: currentSymptom))
                SymptomDetailRow(title: "身体部位", value: currentSymptom.bodyPart.nilIfBlank ?? "")
                SymptomDetailRow(title: "来源", value: SymptomFormSupport.sourceLabel(for: currentSymptom))
                SymptomDetailRow(title: "关联病例", value: SymptomFormSupport.medicalCaseLabel(for: currentSymptom))
            }

            if currentSymptom.notes.nilIfBlank != nil {
                Section("备注") {
                    Text(currentSymptom.notes)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
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
                            Text("删除症状")
                        }
                        Spacer()
                    }
                }
                .disabled(isDeleting)
            }
        }
        .navigationTitle("症状详情")
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
                SymptomFormView(
                    mode: .serverEdit(existing: currentSymptom),
                    submissionService: MedicalRecordFormSubmissionService(workflowAPI: workflowAPI),
                    memberID: memberID,
                    onMutation: { response in
                        if let updated = response.symptom {
                            currentSymptom = updated
                        }
                        onUpdated(response)
                    }
                )
            }
        }
        .alert("确认删除症状？", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await deleteCurrentSymptom() }
            }
        } message: {
            Text("删除后将不再用于成员医疗画像、AI 体检建议和随访摘要。")
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

    private var displayName: String {
        currentSymptom.name.nilIfBlank ?? "未命名症状"
    }

    private var severityText: String {
        let raw = currentSymptom.severity.nilIfBlank ?? ""
        guard raw.isEmpty == false else { return "" }
        return SymptomFormSupport.severityLabel(raw)
    }

    @MainActor
    private func deleteCurrentSymptom() async {
        guard isDeleting == false else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let response = try await MedicalRecordFormSubmissionService(workflowAPI: workflowAPI)
                .submitSymptomDelete(id: currentSymptom.id)
            onDeleted(currentSymptom.id, response)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct SymptomDetailRow: View {
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
