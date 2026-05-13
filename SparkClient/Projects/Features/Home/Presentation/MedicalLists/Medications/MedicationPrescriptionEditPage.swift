import SwiftUI

struct MedicationPrescriptionEditPage: View {
    @Environment(\.dismiss) private var dismiss

    let prescription: SparkMedicalSyncAPI.RemotePrescription
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let notificationClient: any NotificationClient
    let onSaved: (SparkMedicalSyncAPI.RemotePrescription) -> Void
    let onPlanUnlinked: (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void

    @State private var plans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    @State private var institutionName: String
    @State private var prescriberName: String
    @State private var prescriptionNo: String
    @State private var diagnosis: String
    @State private var status: String
    @State private var hasPrescribedAt: Bool
    @State private var prescribedAt: Date
    @State private var isSaving = false
    @State private var unlinkingPlanIDs: Set<Int> = []
    @State private var alertMessage: String?
    @State private var formKeyboardVisible = false

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    init(
        prescription: SparkMedicalSyncAPI.RemotePrescription,
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        onSaved: @escaping (SparkMedicalSyncAPI.RemotePrescription) -> Void,
        onPlanUnlinked: @escaping (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void
    ) {
        self.prescription = prescription
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
        self.onSaved = onSaved
        self.onPlanUnlinked = onPlanUnlinked
        _plans = State(initialValue: plans)
        _institutionName = State(initialValue: prescription.institutionName)
        _prescriberName = State(initialValue: prescription.prescriberName)
        _prescriptionNo = State(initialValue: prescription.prescriptionNo ?? "")
        _diagnosis = State(initialValue: prescription.diagnosis)
        _status = State(initialValue: prescription.status)
        _hasPrescribedAt = State(initialValue: prescription.prescribedAt != nil)
        _prescribedAt = State(initialValue: prescription.prescribedAt ?? Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SparkFormCard(title: "处方信息", titleSystemImage: "doc.text.fill") {
                    VStack(spacing: 14) {
                        SparkFormTextRow(title: "开方机构", text: $institutionName, placeholder: "医院、门诊或药房", keyboardVisible: $formKeyboardVisible)
                        SparkFormTextRow(title: "开方医生", text: $prescriberName, placeholder: "医生姓名", keyboardVisible: $formKeyboardVisible)
                        SparkFormTextRow(title: "处方编号", text: $prescriptionNo, placeholder: "处方号 / 流水号", keyboardVisible: $formKeyboardVisible)
                        SparkFormTextAreaRow(title: "诊断", text: $diagnosis, minHeight: 88, maxHeight: 180, placeholder: "诊断或临床说明", keyboardVisible: $formKeyboardVisible)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                SparkFormCard(title: "开方与状态", titleSystemImage: "calendar.badge.clock") {
                    VStack(spacing: 14) {
                        Toggle("设置开方日期", isOn: $hasPrescribedAt)
                            .font(.subheadline.weight(.medium))
                        if hasPrescribedAt {
                            DatePicker("开方日期", selection: $prescribedAt, displayedComponents: .date)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        Picker("处方状态", selection: $status) {
                            Text("有效").tag("active")
                            Text("草稿").tag("draft")
                            Text("已支付").tag("paid")
                            Text("已发药").tag("dispensed")
                            Text("已完成").tag("completed")
                            Text("已取消").tag("cancelled")
                        }
                        .pickerStyle(.menu)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                linkedMedicationSection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("编辑处方")
        .navigationBarTitleDisplayMode(.inline)
        .sparkFormBottomBar(
            canSubmit: !isSaving,
            saveTitle: saveTitle,
            keyboardVisible: $formKeyboardVisible,
            onCancel: {
                formLog.info("MedicationPrescriptionEditPage: cancel tapped prescriptionId=\(prescription.id)", module: formLogModule)
                dismiss()
            },
            onSave: { saveNow() }
        )
        .alert("保存失败", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var saveTitle: String {
        L10n.text("common.save", fallback: "保存")
    }

    private func saveNow() {
        formLog.info("MedicationPrescriptionEditPage: save started prescriptionId=\(prescription.id)", module: formLogModule)
        Task { await savePrescription() }
    }

    private var linkedMedicationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("关联用药", systemImage: "pills.fill")
                    .font(.headline)
                Spacer()
                Text("\(plans.count) 项")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if plans.isEmpty {
                Text("暂无关联用药计划")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(plans, id: \.id) { plan in
                        EditablePrescriptionMedicationRow(
                            plan: plan,
                            fileTransferService: fileTransferService,
                            isUnlinking: unlinkingPlanIDs.contains(plan.id),
                            onUnlink: {
                                Task { await unlink(plan) }
                            }
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @MainActor
    private func savePrescription() async {
        guard isSaving == false else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let payload = PrescriptionResourceUpdatePayload(
                medicalCase: prescription.medicalCase,
                prescriberName: prescriberName.nilIfBlank,
                institutionName: institutionName.nilIfBlank,
                prescribedAt: hasPrescribedAt ? MedicalDateCoding.encodeDateOnly(prescribedAt) : nil,
                diagnosis: diagnosis.nilIfBlank,
                prescriptionNo: prescriptionNo.nilIfBlank,
                status: status.nilIfBlank ?? "active",
                extra: prescription.extra ?? [:]
            )
            let saved = try await workflowAPI.update(
                SparkMedicalSyncAPI.RemotePrescription.self,
                kind: .prescriptions,
                id: prescription.id,
                body: payload
            )
            onSaved(saved)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
            notificationClient.error(error.localizedDescription, title: "保存失败", source: "home.prescription.edit")
        }
    }

    @MainActor
    private func unlink(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) async {
        guard unlinkingPlanIDs.contains(plan.id) == false else { return }
        unlinkingPlanIDs.insert(plan.id)
        defer { unlinkingPlanIDs.remove(plan.id) }

        do {
            let updated = try await workflowAPI.update(
                SparkMedicalSyncAPI.RemoteMedicationPlan.self,
                kind: .medicationPlans,
                id: plan.id,
                body: MedicationPlanPrescriptionUpdatePayload(prescription: nil)
            )
            plans.removeAll { $0.id == plan.id }
            onPlanUnlinked(updated)
        } catch {
            alertMessage = error.localizedDescription
            notificationClient.error(error.localizedDescription, title: "取消关联失败", source: "home.prescription.unlink_medication")
        }
    }
}

private struct EditablePrescriptionMedicationRow: View {
    let plan: SparkMedicalSyncAPI.RemoteMedicationPlan
    let fileTransferService: FileTransferService
    let isUnlinking: Bool
    let onUnlink: () -> Void

    private var imageAttachment: SparkMedicalSyncAPI.RemoteManagedFile? {
        plan.attachments?.first(where: \.isMedicationImageLike)
    }

    private var subtitle: String {
        [
            plan.dosePerTime.nilIfBlank,
            plan.frequencyText.nilIfBlank,
            plan.reminderEnabled ? plan.reminderTimes.map(\.time).joined(separator: ", ").nilIfBlank : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            MedicationImageGlyph(seed: plan.id, attachment: imageAttachment, fileTransferService: fileTransferService)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.drugName.nilIfBlank ?? "未命名药品")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle.isEmpty ? "暂无补充信息" : subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(role: .destructive) {
                onUnlink()
            } label: {
                if isUnlinking {
                    ProgressView()
                } else {
                    Label("取消关联", systemImage: "link.badge.minus")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isUnlinking)
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PrescriptionResourceUpdatePayload: Encodable {
    let medicalCase: Int?
    let prescriberName: String?
    let institutionName: String?
    let prescribedAt: String?
    let diagnosis: String?
    let prescriptionNo: String?
    let status: String
    let extra: [String: String]

    enum CodingKeys: String, CodingKey {
        case medicalCase = "medical_case"
        case prescriberName = "prescriber_name"
        case institutionName = "institution_name"
        case prescribedAt = "prescribed_at"
        case diagnosis
        case prescriptionNo = "prescription_no"
        case status
        case extra
    }
}

