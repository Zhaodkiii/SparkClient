import SwiftUI

struct VisitFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: VisitRecognitionDraft)
        case localEdit(existing: VisitRecognitionDraft, onSubmit: (VisitRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: ((VisitRecognitionDraft) async throws -> Void)?
    let onServerSubmit: ((VisitRecognitionDraft) async throws -> Void)?

    @State private var visitType = ""
    @State private var visitedAt = ""
    @State private var department = ""
    @State private var doctorName = ""
    @State private var visitNo = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode, onCreateSubmit: ((VisitRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: ((VisitRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: VisitRecognitionDraft
        switch mode {
        case .create: seed = .init(visitType: nil, visitedAt: nil, department: nil, doctorName: nil, visitNo: nil, notes: nil)
        case .serverEdit(let existing), .localEdit(let existing, _): seed = existing
        }
        _visitType = State(initialValue: seed.visitType ?? "")
        _visitedAt = State(initialValue: seed.visitedAt ?? "")
        _department = State(initialValue: seed.department ?? "")
        _doctorName = State(initialValue: seed.doctorName ?? "")
        _visitNo = State(initialValue: seed.visitNo ?? "")
        _notes = State(initialValue: seed.notes ?? "")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: navTitle) {
                SparkFormTextRow(title: "就诊类型", text: $visitType)
                SparkFormTextRow(title: "就诊时间", text: $visitedAt, placeholder: "yyyy-MM-dd")
                SparkFormTextRow(title: "科室", text: $department)
                SparkFormTextRow(title: "医生", text: $doctorName)
                SparkFormTextRow(title: "就诊号", text: $visitNo)
                SparkFormTextAreaRow(title: "备注", text: $notes)
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(saveTitle) { saveNow() }.disabled(isSaving) } }
        .alert("提交失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("好", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var navTitle: String {
        switch mode { case .create: return "新增就诊"; case .serverEdit: return "编辑就诊"; case .localEdit: return "编辑就诊（本地）" }
    }
    private var saveTitle: String {
        switch mode { case .create: return "保存"; case .serverEdit: return "更新"; case .localEdit: return "完成" }
    }
    private var outputDraft: VisitRecognitionDraft {
        .init(visitType: visitType.nilIfBlank, visitedAt: visitedAt.nilIfBlank, department: department.nilIfBlank, doctorName: doctorName.nilIfBlank, visitNo: visitNo.nilIfBlank, notes: notes.nilIfBlank)
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
