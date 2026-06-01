import SwiftUI

struct MedicationPrescriptionDetailPage: View {
    @Environment(\.dismiss) private var dismiss

    let memberID: Int?
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    @ObservedObject var memberContextStore: MemberContextStore
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let notificationClient: any NotificationClient
    let onPrescriptionSaved: (SparkMedicalSyncAPI.RemotePrescription) -> Void
    let onPrescriptionDeleted: (Int) -> Void
    let onPlanSaved: (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void
    let onPlanDeleted: (Int) -> Void
    var onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)?
    var onMedicalCaseDeleted: ((Int) -> Void)?

    @State private var currentPrescription: SparkMedicalSyncAPI.RemotePrescription?
    @State private var currentPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    @State private var medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]]
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var deleteLinkedPlans = false
    @State private var isDeleting = false
    @State private var alertMessage: String?

    init(
        prescription: SparkMedicalSyncAPI.RemotePrescription?,
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]],
        memberID: Int?,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        memberContextStore: MemberContextStore,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        onPrescriptionSaved: @escaping (SparkMedicalSyncAPI.RemotePrescription) -> Void,
        onPrescriptionDeleted: @escaping (Int) -> Void,
        onPlanSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void,
        onPlanDeleted: @escaping (Int) -> Void,
        onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)? = nil,
        onMedicalCaseDeleted: ((Int) -> Void)? = nil
    ) {
        _currentPrescription = State(initialValue: prescription)
        _currentPlans = State(initialValue: plans)
        _medicineBoxesByID = State(initialValue: Dictionary(uniqueKeysWithValues: medicineBoxes.map { ($0.id, $0) }))
        _recordsByPlanID = State(initialValue: recordsByPlanID)
        self.memberID = memberID
        self.completeData = completeData
        self.memberContextStore = memberContextStore
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
        self.onPrescriptionSaved = onPrescriptionSaved
        self.onPrescriptionDeleted = onPrescriptionDeleted
        self.onPlanSaved = onPlanSaved
        self.onPlanDeleted = onPlanDeleted
        self.onMedicalCaseUpdated = onMedicalCaseUpdated
        self.onMedicalCaseDeleted = onMedicalCaseDeleted
    }

    private var title: String {
        currentPrescription?.institutionName.nilIfBlank ?? L10n.text("home.medical.prescription.detail.title")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                diagnosisCard
                attachmentsSection
                medicationSection
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label(L10n.text("common.edit"), systemImage: "pencil")
                    }
                    .disabled(memberID == nil || currentPrescription == nil)

                    Button(role: .destructive) {
                        deleteLinkedPlans = false
                        showingDeleteConfirm = true
                    } label: {
                        Label(L10n.text("common.delete"), systemImage: "trash")
                    }
                    .disabled(currentPrescription == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let currentPrescription {
                CompatibleNavigationContainer {
                    MedicationPrescriptionEditPage(
                        prescription: currentPrescription,
                        plans: currentPlans,
                        workflowAPI: workflowAPI,
                        fileTransferService: fileTransferService,
                        notificationClient: notificationClient,
                        onSaved: { saved in
                            self.currentPrescription = saved
                            onPrescriptionSaved(saved)
                        },
                        onPlanUnlinked: { plan in
                            currentPlans.removeAll { $0.id == plan.id }
                            onPlanSaved(plan)
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showingDeleteConfirm) {
            deleteConfirmSheet
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func prescriptionMedicalCaseLinkSection(prescription: SparkMedicalSyncAPI.RemotePrescription) -> some View {
        MedicalResourceMedicalCaseLinkSection(
            memberID: prescription.member,
            medicalCaseID: prescription.medicalCase,
            resourceKind: .prescriptions,
            resourceID: prescription.id,
            patchField: .medicalCase,
            workflowAPI: workflowAPI,
            fileTransferService: fileTransferService,
            completeData: completeData,
            memberContextStore: memberContextStore,
            notificationClient: notificationClient,
            linkedTitle: L10n.text("home.medical.list.medications.linked_case.title"),
            linkedSubtitle: L10n.text("home.medical.list.medications.linked_case.subtitle"),
            unlinkedTitle: L10n.text("home.medical.list.medications.unlinked_case.title"),
            unlinkedSubtitle: L10n.text("home.medical.list.medications.unlinked_case.subtitle"),
            onResourceUpdated: { (updated: SparkMedicalSyncAPI.RemotePrescription) in
                currentPrescription = updated
                onPrescriptionSaved(updated)
            },
            onMedicalCaseUpdated: onMedicalCaseUpdated,
            onMedicalCaseDeleted: onMedicalCaseDeleted
        )
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(uiColor: .systemPurple), Color(uiColor: .systemIndigo)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "doc.text.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 6) {
                    Text(currentPrescription?.institutionName.nilIfBlank ?? L10n.text("home.medical.prescription.batch_fallback_title"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
            }

            detailGrid
            
            
            if let prescription = currentPrescription {
                prescriptionMedicalCaseLinkSection(prescription: prescription)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var headerSubtitle: String {
        [
            currentPrescription?.prescriberName.nilIfBlank.map {
                String(format: L10n.text("home.medical.prescription.header.doctor_format"), $0)
            },
            currentPrescription?.prescriptionNo?.nilIfBlank.map {
                String(format: L10n.text("home.medical.prescription.header.rx_no_format"), $0)
            },
            currentPrescription?.prescribedAt.map { $0.formatted(date: .abbreviated, time: .omitted) }
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var detailGrid: some View {
        VStack(spacing: 10) {
            PrescriptionDetailInfoRow(
                title: L10n.text("home.medical.prescription.field.status"),
                value: currentPrescription?.status.nilIfBlank.map(prescriptionStatusText) ?? L10n.text("home.medical.medicine_box.not_filled")
            )
            PrescriptionDetailInfoRow(
                title: L10n.text("home.medical.prescription.field.institution"),
                value: currentPrescription?.institutionName.nilIfBlank ?? L10n.text("home.medical.medicine_box.not_filled")
            )
            PrescriptionDetailInfoRow(
                title: L10n.text("home.medical.prescription.field.prescriber"),
                value: currentPrescription?.prescriberName.nilIfBlank ?? L10n.text("home.medical.medicine_box.not_filled")
            )
            PrescriptionDetailInfoRow(
                title: L10n.text("home.medical.prescription.field.prescription_no"),
                value: currentPrescription?.prescriptionNo?.nilIfBlank ?? L10n.text("home.medical.medicine_box.not_filled")
            )
            PrescriptionDetailInfoRow(
                title: L10n.text("home.medical.prescription.field.prescribed_at"),
                value: currentPrescription?.prescribedAt.map { $0.formatted(date: .abbreviated, time: .omitted) }
                    ?? L10n.text("home.medical.medicine_box.not_filled")
            )
        }
    }

    @ViewBuilder
    private var attachmentsSection: some View {
        if let attachments = currentPrescription?.attachments, attachments.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.text("common.attachments"), systemImage: "paperclip")
                    .font(.headline)
                MedicalAttachmentGridPreview(
                    attachments: attachments,
                    fileTransferService: fileTransferService
                )
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var diagnosisCard: some View {
        if let diagnosis = currentPrescription?.diagnosis.nilIfBlank {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.text("common.diagnosis"), systemImage: "stethoscope")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                Text(diagnosis)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Color(uiColor: .systemBlue).opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(uiColor: .systemBlue).opacity(0.16), lineWidth: 1)
            )
        }
    }

    private var medicationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("home.medical.prescription.linked_medications"), systemImage: "pills.fill")
                    .font(.headline)
                Spacer()
                Text(String(format: L10n.text("home.medical.prescription.linked_count"), currentPlans.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if currentPlans.isEmpty {
                Text(L10n.text("home.medical.prescription.no_linked_plans"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(currentPlans, id: \.id) { plan in
                        PrescriptionMedicationPlanSummaryRow(
                            plan: plan,
                            medicineBox: plan.medicineBox.flatMap { medicineBoxesByID[$0] },
                            records: recordsByPlanID[plan.id] ?? [],
                            fileTransferService: fileTransferService,
                            planDetailNavigation: PrescriptionMedicationPlanSummaryRow.PlanDetailNavigation(
                                medicineBoxes: Array(medicineBoxesByID.values),
                                memberID: memberID,
                                completeData: completeData,
                                memberContextStore: memberContextStore,
                                workflowAPI: workflowAPI,
                                notificationClient: notificationClient,
                                onPlanSaved: { updated in
                                    if let idx = currentPlans.firstIndex(where: { $0.id == updated.id }) {
                                        currentPlans[idx] = updated
                                    }
                                    onPlanSaved(updated)
                                },
                                onPlanDeleted: { id in
                                    currentPlans.removeAll { $0.id == id }
                                    onPlanDeleted(id)
                                },
                                onMedicineBoxSaved: { box in
                                    medicineBoxesByID[box.id] = box
                                },
                                onMedicineBoxDeleted: nil
                            )
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var deleteConfirmSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("home.medical.prescription.delete.title"))
                .font(.title3.weight(.semibold))
            Text(L10n.text("home.medical.prescription.delete.message"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(L10n.text("home.medical.prescription.delete.linked_plans"), isOn: $deleteLinkedPlans)
                .font(.subheadline.weight(.medium))
                .toggleStyle(.switch)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button(L10n.text("common.cancel")) {
                    showingDeleteConfirm = false
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button(role: .destructive) {
                    Task { await deleteCurrentPrescription() }
                } label: {
                    if isDeleting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(L10n.text("home.medical.medicine_box.delete.confirm_title"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDeleting)
            }
        }
        .padding(20)
    }

    @MainActor
    private func deleteCurrentPrescription() async {
        guard let prescription = currentPrescription, isDeleting == false else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            if deleteLinkedPlans {
                for plan in currentPlans {
                    try await workflowAPI.delete(kind: .medicationPlans, id: plan.id)
                    onPlanDeleted(plan.id)
                }
            } else {
                for plan in currentPlans {
                    let updated = try await workflowAPI.update(
                        SparkMedicalSyncAPI.RemoteMedicationPlan.self,
                        kind: .medicationPlans,
                        id: plan.id,
                        body: MedicationPlanPrescriptionUpdatePayload(prescription: nil)
                    )
                    onPlanSaved(updated)
                }
            }

            try await workflowAPI.delete(kind: .prescriptions, id: prescription.id)
            onPrescriptionDeleted(prescription.id)
            showingDeleteConfirm = false
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
            notificationClient.error(
                error.localizedDescription,
                title: L10n.text("home.medical.prescription.delete.failed"),
                source: "home.prescription.delete"
            )
        }
    }
}

private struct PrescriptionDetailInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private func prescriptionStatusText(_ status: String) -> String {
    switch status {
    case "active":
        return L10n.text("home.medical.prescription.status.active")
    case "draft":
        return L10n.text("home.medical.prescription.status.draft")
    case "paid":
        return L10n.text("home.medical.prescription.status.paid")
    case "dispensed":
        return L10n.text("home.medical.prescription.status.dispensed")
    case "completed":
        return L10n.text("home.medical.prescription.status.completed")
    case "cancelled":
        return L10n.text("home.medical.prescription.status.cancelled")
    default:
        return status
    }
}

struct MedicationPlanPrescriptionUpdatePayload: Encodable {
    let prescription: Int?


    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodableKey.self)
        if let prescription {
            try container.encode(prescription, forKey: .key("prescription"))
        } else {
            try container.encodeNil(forKey: .key("prescription"))
        }
    }
}
