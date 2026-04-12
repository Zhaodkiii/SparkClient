import SwiftUI

struct FollowUpFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: FollowUpRecognitionDraft)
        case localEdit(existing: FollowUpRecognitionDraft, onSubmit: (FollowUpRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: ((FollowUpRecognitionDraft) async throws -> Void)?
    let onServerSubmit: ((FollowUpRecognitionDraft) async throws -> Void)?

    @State private var plannedAt = ""
    @State private var completedAt = ""
    @State private var status = ""
    @State private var method = ""
    @State private var outcome = ""
    @State private var nextAction = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode, onCreateSubmit: ((FollowUpRecognitionDraft) async throws -> Void)? = nil, onServerSubmit: ((FollowUpRecognitionDraft) async throws -> Void)? = nil) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: FollowUpRecognitionDraft
        switch mode {
        case .create: seed = .init(plannedAt: nil, completedAt: nil, status: nil, method: nil, outcome: nil, nextAction: nil)
        case .serverEdit(let existing), .localEdit(let existing, _): seed = existing
        }
        _plannedAt = State(initialValue: seed.plannedAt ?? "")
        _completedAt = State(initialValue: seed.completedAt ?? "")
        _status = State(initialValue: seed.status ?? "")
        _method = State(initialValue: seed.method ?? "")
        _outcome = State(initialValue: seed.outcome ?? "")
        _nextAction = State(initialValue: seed.nextAction ?? "")
    }

    var body: some View {
        ScrollView {
            SparkFormCard(title: navTitle) {
                SparkFormTextRow(title: "计划时间", text: $plannedAt)
                SparkFormTextRow(title: "完成时间", text: $completedAt)
                SparkFormTextRow(title: "状态", text: $status)
                SparkFormTextRow(title: "方式", text: $method)
                SparkFormTextAreaRow(title: "结果", text: $outcome)
                SparkFormTextAreaRow(title: "下一步计划", text: $nextAction)
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(saveTitle) { saveNow() }.disabled(isSaving) } }
        .alert("提交失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("好", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var navTitle: String { switch mode { case .create: return "新增随访"; case .serverEdit: return "编辑随访"; case .localEdit: return "编辑随访（本地）" } }
    private var saveTitle: String { switch mode { case .create: return "保存"; case .serverEdit: return "更新"; case .localEdit: return "完成" } }
    private var outputDraft: FollowUpRecognitionDraft {
        .init(plannedAt: plannedAt.nilIfBlank, completedAt: completedAt.nilIfBlank, status: status.nilIfBlank, method: method.nilIfBlank, outcome: outcome.nilIfBlank, nextAction: nextAction.nilIfBlank)
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
