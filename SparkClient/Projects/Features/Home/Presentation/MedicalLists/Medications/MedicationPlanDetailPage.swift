import SwiftUI

struct MedicationPlanDetailPage: View {
    let plan: SparkMedicalSyncAPI.RemoteMedicationPlan
    let records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    let memberID: Int?
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    @ObservedObject var memberContextStore: MemberContextStore
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let notificationClient: any NotificationClient
    let onSaved: (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void
    let onDeleted: (Int) -> Void
    let onMedicineBoxSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    var onMedicineBoxDeleted: ((Int) -> Void)?
    var onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)?
    var onMedicalCaseDeleted: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var currentPlan: SparkMedicalSyncAPI.RemoteMedicationPlan
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var alertMessage: String?

    init(
        plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        memberID: Int?,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        memberContextStore: MemberContextStore,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        onSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicationPlan) -> Void,
        onDeleted: @escaping (Int) -> Void,
        onMedicineBoxSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onMedicineBoxDeleted: ((Int) -> Void)? = nil,
        onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)? = nil,
        onMedicalCaseDeleted: ((Int) -> Void)? = nil
    ) {
        self.plan = plan
        self.records = records
        self.memberID = memberID
        self.completeData = completeData
        self.memberContextStore = memberContextStore
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.onMedicineBoxSaved = onMedicineBoxSaved
        self.onMedicineBoxDeleted = onMedicineBoxDeleted
        self.onMedicalCaseUpdated = onMedicalCaseUpdated
        self.onMedicalCaseDeleted = onMedicalCaseDeleted
        _currentPlan = State(initialValue: plan)
        _medicineBoxes = State(initialValue: medicineBoxes)
    }

    private var sortedRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord] {
        records.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var medicineBox: SparkMedicalSyncAPI.RemoteMedicineBox? {
        currentPlan.medicineBox.flatMap { id in
            medicineBoxes.first(where: { $0.id == id })
        }
    }

    var body: some View {
        List {
         
            if let medicineBox {
                Section(L10n.text("home.medical.medication_plan.section.linked_box")) {
                    MainNavigationLink {
                        MedicineBoxDetailPage(
                            box: medicineBox,
                            entryMemberID: memberID,
                            typeOptions: MedicineBoxTypeCatalog.options(in: medicineBoxes),
                            specOptionBoxes: medicineBoxes,
                            workflowAPI: workflowAPI,
                            fileTransferService: fileTransferService,
                            onSaved: handleMedicineBoxSaved,
                            onDeleted: handleMedicineBoxDeleted
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox.fill")
                                .font(.headline)
                                .foregroundStyle(Color(uiColor: .systemPurple))
                                .frame(width: 36, height: 36)
                                .background(Color(uiColor: .systemPurple).opacity(0.12), in: Circle())
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(medicationPlanDetailLinkedBoxTitle(medicineBox))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(medicationPlanDetailLinkedBoxSubtitle(medicineBox))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
             
            }else if currentPlan.medicineBox != nil {
                MedicationPlanDetailInfoRow(
                    title: L10n.text("home.medical.medication_plan.section.linked_box"),
                    value: L10n.text("home.medical.medication_plan.box_unavailable")
                )
            }
            
            Section(L10n.text("home.medical.medication_plan.section.plan")) {
                MedicationPlanDetailInfoRow(title: L10n.text("home.medical.medication_plan.field.drug"), value: currentPlan.drugName)
                MedicationPlanDetailInfoRow(title: L10n.text("home.medical.list.medications.dose_short"), value: currentPlan.dosePerTime)
                MedicationPlanDetailInfoRow(title: L10n.text("home.medical.list.medications.frequency_title"), value: currentPlan.frequencyText)
                MedicationPlanDetailInfoRow(
                    title: L10n.text("home.medical.medication_plan.field.reminder"),
                    value: currentPlan.reminderTimes.map(\.time).joined(separator: ", ")
                )
                MedicationPlanDetailInfoRow(
                    title: L10n.text("common.status"),
                    value: medicationPlanDetailStatusLabel(currentPlan.status)
                )
                if currentPlan.instructions.isEmpty == false {
                    MedicationPlanDetailInfoRow(
                        title: L10n.text("medical_record.forms.field.instructions"),
                        value: currentPlan.instructions
                    )
                }
                
                MedicalResourceMedicalCaseLinkSection(
                    memberID: currentPlan.member,
                    medicalCaseID: currentPlan.medicalCase,
                    resourceKind: .medicationPlans,
                    resourceID: currentPlan.id,
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
                    onResourceUpdated: { (updated: SparkMedicalSyncAPI.RemoteMedicationPlan) in
                        currentPlan = updated
                        onSaved(updated)
                    },
                    onMedicalCaseUpdated: onMedicalCaseUpdated,
                    onMedicalCaseDeleted: onMedicalCaseDeleted
                )
            }
            
            if let attachments = currentPlan.attachments, attachments.isEmpty == false {
                Section(L10n.text("common.attachments")) {
                    MedicalAttachmentGridPreview(
                        attachments: attachments,
                        fileTransferService: fileTransferService
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            Section(L10n.text("home.medical.medication_plan.section.records")) {
                if sortedRecords.isEmpty {
                    Text(L10n.text("home.medical.medication_plan.no_records"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedRecords, id: \.id) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(record.scheduledAt.formatted(date: .omitted, time: .shortened))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(medicationPlanDetailRecordStatusLabel(record.status))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(record.status == "taken" ? Color(uiColor: .systemGreen) : Color(uiColor: .secondaryLabel))
                            }
                            Text(String(format: L10n.text("home.medical.medication_plan.record.planned_dose_format"), record.plannedDose))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let takenAt = record.takenAt {
                                Text(
                                    String(
                                        format: L10n.text("home.medical.medication_plan.record.taken_at_format"),
                                        takenAt.formatted(date: .omitted, time: .shortened)
                                    )
                                )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if record.actualDose.isEmpty == false {
                                Text(
                                    String(
                                        format: L10n.text("home.medical.medication_plan.record.actual_dose_format"),
                                        record.actualDose
                                    )
                                )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(currentPlan.drugName.nilIfBlank ?? L10n.text("home.medical.medication_plan.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label(L10n.text("common.edit"), systemImage: "pencil")
                    }
                    .disabled(memberID == nil)

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label(L10n.text("common.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let memberID {
                MedicationPlanFormView(
                    mode: .serverEdit(existing: currentPlan),
                    memberID: memberID,
                    medicineBoxes: medicineBoxes,
                    workflowAPI: workflowAPI,
                    fileTransferService: fileTransferService,
                    notificationClient: notificationClient,
                    onMedicineBoxSaved: handleMedicineBoxSaved,
                    onServerSaved: { saved in
                        currentPlan = saved
                        onSaved(saved)
                        showingEditSheet = false
                    }
                )
            } else {
                Text(L10n.text("home.medical.medicine_box.select_member_first"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert(L10n.text("home.medical.medicine_box.delete.confirm_title"), isPresented: $showingDeleteConfirm) {
            Button(L10n.text("common.cancel"), role: .cancel) {}
            Button(L10n.text("common.delete"), role: .destructive) {
                Task { await deleteCurrentPlan() }
            }
        } message: {
            Text(L10n.text("home.medical.medication_plan.delete.message"))
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button(L10n.text("common.got_it"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onChange(of: plan) { newValue in
            currentPlan = newValue
        }
    }

    private func handleMedicineBoxSaved(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
            medicineBoxes[index] = box
        } else {
            medicineBoxes.insert(box, at: 0)
        }
        onMedicineBoxSaved(box)
    }

    private func handleMedicineBoxDeleted(_ id: Int) {
        medicineBoxes.removeAll { $0.id == id }
        onMedicineBoxDeleted?(id)
    }

    @MainActor
    private func deleteCurrentPlan() async {
        guard isDeleting == false else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await workflowAPI.delete(kind: .medicationPlans, id: currentPlan.id)
            onDeleted(currentPlan.id)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct MedicationPlanDetailInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.isEmpty ? L10n.text("home.medical.medicine_box.not_filled") : value)
                .multilineTextAlignment(.trailing)
        }
    }
}

private func medicationPlanDetailStockText(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
    guard let q = box.totalQuantity else { return L10n.text("home.medical.medication_plan.stock_not_filled") }
    return String(
        format: L10n.text("home.medical.medication_plan.stock_format"),
        q.formatted(.number.precision(.fractionLength(0...2)))
    )
}

private func medicationPlanDetailLinkedBoxTitle(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
    box.medicineName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed")
}

private func medicationPlanDetailLinkedBoxSubtitle(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
    let detail = [box.strength.nilIfBlank, box.dosageForm.nilIfBlank, medicationPlanDetailStockText(box)]
        .compactMap { $0 }
        .joined(separator: " · ")
    return detail.isEmpty ? L10n.text("home.medical.medication_plan.linked_box_fallback") : detail
}

private func medicationPlanDetailStatusLabel(_ status: String) -> String {
    switch status {
    case "active":
        return L10n.text("home.medical.medication_plan.detail.status.active")
    case "paused":
        return L10n.text("home.medical.medication_plan.detail.status.paused")
    case "completed":
        return L10n.text("home.medical.medication_plan.detail.status.completed")
    case "cancelled":
        return L10n.text("home.medical.medication_plan.detail.status.cancelled")
    default:
        return status
    }
}

private func medicationPlanDetailRecordStatusLabel(_ status: String) -> String {
    switch status {
    case "scheduled":
        return L10n.text("home.medical.medication_plan.record.status.scheduled")
    case "taken":
        return L10n.text("home.medical.medication_plan.record.status.taken")
    case "skipped":
        return L10n.text("home.medical.medication_plan.record.status.skipped")
    case "snoozed":
        return L10n.text("home.medical.medication_plan.record.status.snoozed")
    default:
        return status
    }
}
