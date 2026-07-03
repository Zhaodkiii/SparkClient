import SwiftUI

struct MedicationPrescriptionEditPage: View {
    enum Mode {
        case create
        case serverEdit(existing: SparkMedicalSyncAPI.RemotePrescription)
        case localEdit(existing: PrescriptionRecognitionDraft, onSubmit: (PrescriptionRecognitionDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
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
        self.mode = .serverEdit(existing: prescription)
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

    init(
        mode: Mode,
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan] = [],
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        onSaved: @escaping (SparkMedicalSyncAPI.RemotePrescription) -> Void = { _ in },
        onPlanUnlinked: @escaping (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void = { _ in }
    ) {
        self.mode = mode
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
        self.onSaved = onSaved
        self.onPlanUnlinked = onPlanUnlinked

        let seedPrescription: SparkMedicalSyncAPI.RemotePrescription
        switch mode {
        case .create:
            seedPrescription = SparkMedicalSyncAPI.RemotePrescription(
                id: 0,
                member: 0,
                medicalCase: nil,
                prescriberName: "",
                institutionName: "",
                prescribedAt: nil,
                diagnosis: "",
                prescriptionNo: nil,
                status: "active",
                extra: nil,
                attachments: nil,
                updatedAt: Date()
            )
        case .serverEdit(let existing):
            seedPrescription = existing
        case .localEdit(let existing, _):
            let date = MedicalDateCoding.decodeDateOnlyOrDefaultNow(existing.prescribedAt, defaultDate: Date())
            seedPrescription = SparkMedicalSyncAPI.RemotePrescription(
                id: 0,
                member: 0,
                medicalCase: existing.medicalCase,
                prescriberName: existing.prescriberName ?? "",
                institutionName: existing.institutionName ?? "",
                prescribedAt: existing.prescribedAt == nil ? nil : date,
                diagnosis: existing.diagnosis ?? "",
                prescriptionNo: existing.prescriptionNo,
                status: existing.status ?? "active",
                extra: existing.extra,
                attachments: nil,
                updatedAt: Date()
            )
        }

        self.prescription = seedPrescription
        _plans = State(initialValue: plans)
        _institutionName = State(initialValue: seedPrescription.institutionName)
        _prescriberName = State(initialValue: seedPrescription.prescriberName)
        _prescriptionNo = State(initialValue: seedPrescription.prescriptionNo ?? "")
        _diagnosis = State(initialValue: seedPrescription.diagnosis)
        _status = State(initialValue: seedPrescription.status)
        _hasPrescribedAt = State(initialValue: seedPrescription.prescribedAt != nil)
        _prescribedAt = State(initialValue: seedPrescription.prescribedAt ?? Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SparkFormCard(title: L10n.text("home.medical.prescription.section.info"), titleSystemImage: "doc.text.fill") {
                    VStack(spacing: 14) {
                        SparkFormTextRow(
                            title: L10n.text("home.medical.prescription.field.institution"),
                            text: $institutionName,
                            placeholder: L10n.text("home.medical.prescription.placeholder.institution"),
                            keyboardVisible: $formKeyboardVisible
                        )
                        SparkFormTextRow(
                            title: L10n.text("home.medical.prescription.field.prescriber"),
                            text: $prescriberName,
                            placeholder: L10n.text("home.medical.prescription.placeholder.prescriber"),
                            keyboardVisible: $formKeyboardVisible
                        )
                        SparkFormTextRow(
                            title: L10n.text("home.medical.prescription.field.prescription_no"),
                            text: $prescriptionNo,
                            placeholder: L10n.text("home.medical.prescription.placeholder.prescription_no"),
                            keyboardVisible: $formKeyboardVisible
                        )
                        SparkFormTextAreaRow(
                            title: L10n.text("common.diagnosis"),
                            text: $diagnosis,
                            minHeight: 88,
                            maxHeight: 180,
                            placeholder: L10n.text("home.medical.prescription.placeholder.diagnosis"),
                            keyboardVisible: $formKeyboardVisible
                        )
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                SparkFormCard(title: L10n.text("home.medical.prescription.section.schedule_status"), titleSystemImage: "calendar.badge.clock") {
                    VStack(spacing: 14) {
                        Toggle(L10n.text("home.medical.prescription.field.set_prescribed_at"), isOn: $hasPrescribedAt)
                            .font(.subheadline.weight(.medium))
                        if hasPrescribedAt {
                            DatePicker(
                                L10n.text("home.medical.prescription.field.prescribed_at"),
                                selection: $prescribedAt,
                                displayedComponents: .date
                            )
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        Picker(L10n.text("home.medical.prescription.field.status"), selection: $status) {
                            ForEach(PrescriptionLifecycleStatus.allCases, id: \.rawValue) { item in
                                Text(PrescriptionLifecycleStatus.displayLabel(for: item.rawValue)).tag(item.rawValue)
                            }
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
        .navigationTitle(L10n.text("home.medical.prescription.edit.title"))
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
        .alert(L10n.text("home.medical.medicine_box.save_failed"), isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var saveTitle: String {
        L10n.text("common.save")
    }

    private func saveNow() {
        formLog.info("MedicationPrescriptionEditPage: save started prescriptionId=\(prescription.id)", module: formLogModule)
        switch mode {
        case .localEdit(let existing, let onSubmit):
            onSubmit(localOutputDraft(existing: existing))
            dismiss()
        case .create, .serverEdit:
            Task { await savePrescription() }
        }
    }

    private var linkedMedicationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("home.medical.prescription.linked_medications"), systemImage: "pills.fill")
                    .font(.headline)
                Spacer()
                Text(L10n.format("home.medical.prescription.linked_count", plans.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if plans.isEmpty {
                Text(L10n.text("home.medical.prescription.no_linked_plans"))
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
                status: PrescriptionFieldNormalization.resolvedLifecycleStatus(status.nilIfBlank),
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
            notificationClient.error(
                error.localizedDescription,
                title: L10n.text("home.medical.medicine_box.save_failed"),
                source: "home.prescription.edit"
            )
        }
    }

    private func localOutputDraft(existing: PrescriptionRecognitionDraft) -> PrescriptionRecognitionDraft {
        PrescriptionRecognitionDraft(
            medicalCase: existing.medicalCase,
            prescriberName: prescriberName.nilIfBlank,
            institutionName: institutionName.nilIfBlank,
            prescribedAt: hasPrescribedAt ? MedicalDateCoding.encodeDateOnly(prescribedAt) : nil,
            diagnosis: diagnosis.nilIfBlank,
            prescriptionNo: prescriptionNo.nilIfBlank,
            status: PrescriptionFieldNormalization.resolvedLifecycleStatus(status.nilIfBlank),
            extra: existing.extra,
            medicationPlans: existing.medicationPlans,
            attachmentFileIds: existing.attachmentFileIds
        )
    }

    @MainActor
    private func unlink(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) async {
        guard unlinkingPlanIDs.contains(plan.id) == false else { return }
        unlinkingPlanIDs.insert(plan.id)
        defer { unlinkingPlanIDs.remove(plan.id) }

        do {
            let mutation = try await workflowAPI.updateMedicationPlan(
                id: plan.id,
                body: MedicationPlanPrescriptionUpdatePayload(prescription: nil)
            )
            guard let updated = mutation.medicationPlan else {
                throw SparkNetworkError.decoding(
                    NSError(
                        domain: "MedicationPrescriptionEditPage",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "用药计划更新响应缺少 medication_plan"]
                    )
                )
            }
            plans.removeAll { $0.id == plan.id }
            onPlanUnlinked(updated)
        } catch {
            alertMessage = error.localizedDescription
            notificationClient.error(
                error.localizedDescription,
                title: L10n.text("home.medical.prescription.unlink_failed"),
                source: "home.prescription.unlink_medication"
            )
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
                Text(plan.drugName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle.isEmpty ? L10n.text("home.medical.prescription.no_supplemental_info") : subtitle)
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
                    Label(L10n.text("home.medical.prescription.unlink"), systemImage: "link.badge.minus")
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

}
