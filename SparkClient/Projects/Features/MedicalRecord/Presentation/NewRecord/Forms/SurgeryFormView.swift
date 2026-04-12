import SwiftUI

struct SurgeryFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: SurgeryRecognitionDraft)
        case localEdit(existing: SurgeryRecognitionDraft, onSubmit: (SurgeryRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: ((SurgeryRecognitionDraft) async throws -> Void)?
    let onServerSubmit: ((SurgeryRecognitionDraft) async throws -> Void)?

    @State private var procedureName = ""
    @State private var procedureCode = ""
    @State private var site = ""
    @State private var performedAt = ""
    @State private var surgeon = ""
    @State private var anesthesiaType = ""
    @State private var incisionLevel = ""
    @State private var asaClass = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode, onCreateSubmit: ((SurgeryRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: ((SurgeryRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: SurgeryRecognitionDraft
        switch mode {
        case .create: seed = .init(procedureName: "", procedureCode: nil, site: nil, performedAt: nil, surgeon: nil, anesthesiaType: nil, incisionLevel: nil, asaClass: nil, notes: nil)
        case .serverEdit(let existing), .localEdit(let existing, _): seed = existing
        }
        _procedureName = State(initialValue: seed.procedureName)
        _procedureCode = State(initialValue: seed.procedureCode ?? "")
        _site = State(initialValue: seed.site ?? "")
        _performedAt = State(initialValue: seed.performedAt ?? "")
        _surgeon = State(initialValue: seed.surgeon ?? "")
        _anesthesiaType = State(initialValue: seed.anesthesiaType ?? "")
        _incisionLevel = State(initialValue: seed.incisionLevel ?? "")
        _asaClass = State(initialValue: seed.asaClass ?? "")
        _notes = State(initialValue: seed.notes ?? "")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: navTitle) {
                SparkFormTextRow(title: "手术名称", text: $procedureName)
                SparkFormTextRow(title: "手术编码", text: $procedureCode)
                SparkFormTextRow(title: "部位", text: $site)
                SparkFormTextRow(title: "手术时间", text: $performedAt, placeholder: "yyyy-MM-dd")
                SparkFormTextRow(title: "主刀医生", text: $surgeon)
                SparkFormTextRow(title: "麻醉方式", text: $anesthesiaType)
                SparkFormTextRow(title: "切口等级", text: $incisionLevel)
                SparkFormTextRow(title: "ASA 分级", text: $asaClass)
                SparkFormTextAreaRow(title: "备注", text: $notes)
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(saveTitle) { saveNow() }.disabled(isSaving) } }
        .alert("提交失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("好", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var navTitle: String { switch mode { case .create: return "新增手术"; case .serverEdit: return "编辑手术"; case .localEdit: return "编辑手术（本地）" } }
    private var saveTitle: String { switch mode { case .create: return "保存"; case .serverEdit: return "更新"; case .localEdit: return "完成" } }
    private var outputDraft: SurgeryRecognitionDraft {
        .init(procedureName: procedureName, procedureCode: procedureCode.nilIfBlank, site: site.nilIfBlank, performedAt: performedAt.nilIfBlank, surgeon: surgeon.nilIfBlank, anesthesiaType: anesthesiaType.nilIfBlank, incisionLevel: incisionLevel.nilIfBlank, asaClass: asaClass.nilIfBlank, notes: notes.nilIfBlank)
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
