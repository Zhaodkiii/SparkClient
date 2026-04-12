import SwiftUI

struct SymptomFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: SymptomRecognitionDraft)
        case localEdit(existing: SymptomRecognitionDraft, onSubmit: (SymptomRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: ((SymptomRecognitionDraft) async throws -> Void)?
    let onServerSubmit: ((SymptomRecognitionDraft) async throws -> Void)?

    @State private var name = ""
    @State private var code = ""
    @State private var severity = ""
    @State private var startedAt = ""
    @State private var durationValue = ""
    @State private var durationUnit = ""
    @State private var bodyPart = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode, onCreateSubmit: ((SymptomRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: ((SymptomRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: SymptomRecognitionDraft
        switch mode {
        case .create: seed = .init(name: "", code: nil, severity: nil, startedAt: nil, durationValue: nil, durationUnit: nil, bodyPart: nil, notes: nil)
        case .serverEdit(let existing), .localEdit(let existing, _): seed = existing
        }
        _name = State(initialValue: seed.name)
        _code = State(initialValue: seed.code ?? "")
        _severity = State(initialValue: seed.severity ?? "")
        _startedAt = State(initialValue: seed.startedAt ?? "")
        _durationValue = State(initialValue: seed.durationValue ?? "")
        _durationUnit = State(initialValue: seed.durationUnit ?? "")
        _bodyPart = State(initialValue: seed.bodyPart ?? "")
        _notes = State(initialValue: seed.notes ?? "")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: navTitle) {
                SparkFormTextRow(title: "症状名称", text: $name)
                SparkFormTextRow(title: "编码", text: $code)
                SparkFormTextRow(title: "严重程度", text: $severity)
                SparkFormTextRow(title: "开始时间", text: $startedAt, placeholder: "yyyy-MM-dd")
                SparkFormTextRow(title: "持续值", text: $durationValue)
                SparkFormTextRow(title: "持续单位", text: $durationUnit)
                SparkFormTextRow(title: "部位", text: $bodyPart)
                SparkFormTextAreaRow(title: "备注", text: $notes)
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(saveTitle) { saveNow() }.disabled(isSaving) } }
        .alert("提交失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("好", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var navTitle: String { switch mode { case .create: return "新增症状"; case .serverEdit: return "编辑症状"; case .localEdit: return "编辑症状（本地）" } }
    private var saveTitle: String { switch mode { case .create: return "保存"; case .serverEdit: return "更新"; case .localEdit: return "完成" } }
    private var outputDraft: SymptomRecognitionDraft {
        .init(name: name, code: code.nilIfBlank, severity: severity.nilIfBlank, startedAt: startedAt.nilIfBlank, durationValue: durationValue.nilIfBlank, durationUnit: durationUnit.nilIfBlank, bodyPart: bodyPart.nilIfBlank, notes: notes.nilIfBlank)
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
