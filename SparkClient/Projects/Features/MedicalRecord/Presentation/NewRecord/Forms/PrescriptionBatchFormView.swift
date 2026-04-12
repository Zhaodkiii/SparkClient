import SwiftUI

struct PrescriptionBatchFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: PrescriptionRecognitionDraft)
        case localEdit(existing: PrescriptionRecognitionDraft, onSubmit: (PrescriptionRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: ((PrescriptionRecognitionDraft) async throws -> Void)?
    let onServerSubmit: ((PrescriptionRecognitionDraft) async throws -> Void)?

    @State private var prescriberName = ""
    @State private var institutionName = ""
    @State private var prescribedAt = ""
    @State private var diagnosis = ""
    @State private var batchNo = ""
    @State private var status = "active"
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode, onCreateSubmit: ((PrescriptionRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: ((PrescriptionRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: PrescriptionRecognitionDraft
        switch mode {
        case .create:
            seed = .init(medicalCase: nil, prescriberName: nil, institutionName: nil, prescribedAt: nil, diagnosis: nil, batchNo: nil, status: "active", auditorName: nil, auditedAt: nil, extra: nil, medications: [])
        case .serverEdit(let existing), .localEdit(let existing, _): seed = existing
        }

        _prescriberName = State(initialValue: seed.prescriberName ?? "")
        _institutionName = State(initialValue: seed.institutionName ?? "")
        _prescribedAt = State(initialValue: seed.prescribedAt ?? "")
        _diagnosis = State(initialValue: seed.diagnosis ?? "")
        _batchNo = State(initialValue: seed.batchNo ?? "")
        _status = State(initialValue: seed.status ?? "active")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: navTitle) {
                SparkFormTextRow(title: "开方医生", text: $prescriberName)
                SparkFormTextRow(title: "机构", text: $institutionName)
                SparkFormTextRow(title: "开方时间", text: $prescribedAt)
                SparkFormTextRow(title: "诊断", text: $diagnosis)
                SparkFormTextRow(title: "批次号", text: $batchNo)
                SparkFormTextRow(title: "状态", text: $status)
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(saveTitle) { saveNow() }.disabled(isSaving) } }
        .alert("提交失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("好", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var navTitle: String { switch mode { case .create: return "新增处方批次"; case .serverEdit: return "编辑处方批次"; case .localEdit: return "编辑处方批次（本地）" } }
    private var saveTitle: String { switch mode { case .create: return "保存"; case .serverEdit: return "更新"; case .localEdit: return "完成" } }
    private var outputDraft: PrescriptionRecognitionDraft {
        .init(medicalCase: nil, prescriberName: prescriberName.nilIfBlank, institutionName: institutionName.nilIfBlank, prescribedAt: prescribedAt.nilIfBlank, diagnosis: diagnosis.nilIfBlank, batchNo: batchNo.nilIfBlank, status: status.nilIfBlank, auditorName: nil, auditedAt: nil, extra: nil, medications: [])
    }

    private func saveNow() {
        let draft = outputDraft
        switch mode {
        case .localEdit(_, let onSubmit): onSubmit(draft); dismiss()
        case .create:
            guard let onCreateSubmit else { dismiss(); return }
            isSaving = true
            Task { do { try await onCreateSubmit(draft); await MainActor.run { dismiss() } } catch { await MainActor.run { errorMessage = error.localizedDescription } }; await MainActor.run { isSaving = false } }
        case .serverEdit:
            guard let onServerSubmit else { dismiss(); return }
            isSaving = true
            Task { do { try await onServerSubmit(draft); await MainActor.run { dismiss() } } catch { await MainActor.run { errorMessage = error.localizedDescription } }; await MainActor.run { isSaving = false } }
        }
    }
}
