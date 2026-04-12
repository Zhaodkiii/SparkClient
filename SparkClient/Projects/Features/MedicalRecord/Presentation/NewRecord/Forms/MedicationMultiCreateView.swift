import SwiftUI

struct MedicationMultiCreateView: View {
    enum Mode {
        case create
        case serverEdit(existing: PrescriptionRecognitionDraft)
        case localEdit(existing: PrescriptionRecognitionDraft, onSubmit: (PrescriptionRecognitionDraft) -> Void)
    }

    struct MedicationItemDraft: Identifiable {
        var id = UUID()
        var drugName: String = ""
        var genericName: String = ""
        var strength: String = ""
        var frequencyText: String = ""
        var dosePerTime: String = ""
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
    @State private var items: [MedicationItemDraft] = []
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
        _items = State(initialValue: (seed.medications ?? []).map {
            MedicationItemDraft(drugName: $0.drugName ?? "", genericName: $0.genericName ?? "", strength: $0.strength ?? "", frequencyText: $0.frequencyText ?? "", dosePerTime: $0.dosePerTime ?? "")
        })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SparkFormCard(title: "处方批次") {
                    SparkFormTextRow(title: "开方医生", text: $prescriberName)
                    SparkFormTextRow(title: "机构", text: $institutionName)
                    SparkFormTextRow(title: "开方时间", text: $prescribedAt)
                    SparkFormTextRow(title: "诊断", text: $diagnosis)
                    SparkFormTextRow(title: "批次号", text: $batchNo)
                    SparkFormTextRow(title: "状态", text: $status)
                }

                SparkFormCard(title: "用药列表") {
                    Button("新增一条") { items.append(.init()) }
                        .buttonStyle(.bordered)

                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 6) {
                            SparkFormTextRow(title: "药名", text: $item.drugName)
                            SparkFormTextRow(title: "通用名", text: $item.genericName)
                            SparkFormTextRow(title: "规格", text: $item.strength)
                            SparkFormTextRow(title: "频次", text: $item.frequencyText)
                            SparkFormTextRow(title: "每次剂量", text: $item.dosePerTime)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(saveTitle) { saveNow() }.disabled(isSaving) } }
        .alert("提交失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("好", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var navTitle: String { switch mode { case .create: return "批量新增用药"; case .serverEdit: return "编辑批次用药"; case .localEdit: return "编辑批次用药（本地）" } }
    private var saveTitle: String { switch mode { case .create: return "保存"; case .serverEdit: return "更新"; case .localEdit: return "完成" } }

    private var outputDraft: PrescriptionRecognitionDraft {
        let meds = items.enumerated().map { index, item in
            MedicationRecognitionDraft(
                genericName: item.genericName.nilIfBlank,
                brandName: nil,
                drugName: item.drugName.nilIfBlank,
                dosageForm: nil,
                strength: item.strength.nilIfBlank,
                route: nil,
                dosePerTime: item.dosePerTime.nilIfBlank,
                doseValue: nil,
                doseUnit: nil,
                frequencyCode: nil,
                period: nil,
                timesPerPeriod: nil,
                frequencyText: item.frequencyText.nilIfBlank,
                durationDays: nil,
                instructions: nil,
                reminderEnabled: false,
                reminderTimes: [],
                sortOrder: "\(index)",
                extra: nil
            )
        }
        return .init(
            medicalCase: nil,
            prescriberName: prescriberName.nilIfBlank,
            institutionName: institutionName.nilIfBlank,
            prescribedAt: prescribedAt.nilIfBlank,
            diagnosis: diagnosis.nilIfBlank,
            batchNo: batchNo.nilIfBlank,
            status: status.nilIfBlank,
            auditorName: nil,
            auditedAt: nil,
            extra: nil,
            medications: meds
        )
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
