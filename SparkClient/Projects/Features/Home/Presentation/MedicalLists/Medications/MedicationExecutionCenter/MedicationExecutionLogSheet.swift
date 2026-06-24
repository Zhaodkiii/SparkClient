import SwiftUI

struct MedicationExecutionLogSheet: View {
    let context: MedicationExecutionLogSheetContext
    let isSaving: Bool
    let fileTransferService: FileTransferService
    let memberID: Int?
    let homeDependencies: HomeFeatureDependencies?
    let medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let medicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    let onMedicineBoxesChanged: (([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void)?
    let onMedicineBoxAdded: () -> Void
    let onCancel: () -> Void
    let onDone: (MedicationExecutionLogSubmission) -> Void
    let embedInNavigationView: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selections: [MedicationExecutionDose.ID: MedicationDoseLogStatus]
    @State private var doseEdits: [MedicationExecutionDose.ID: MedicationExecutionDoseEdit]
    @State private var doseDetailRoute: MedicationExecutionDoseDetailRoute?

    private let calendar = Calendar.current

    init(
        context: MedicationExecutionLogSheetContext,
        isSaving: Bool,
        fileTransferService: FileTransferService,
        memberID: Int? = nil,
        homeDependencies: HomeFeatureDependencies? = nil,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] = [],
        medicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan] = [],
        onMedicineBoxesChanged: (([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void)? = nil,
        onMedicineBoxAdded: @escaping () -> Void = {},
        onCancel: @escaping () -> Void,
        onDone: @escaping (MedicationExecutionLogSubmission) -> Void,
        embedInNavigationView: Bool = true
    ) {
        self.context = context
        self.isSaving = isSaving
        self.fileTransferService = fileTransferService
        self.memberID = memberID
        self.homeDependencies = homeDependencies
        self.medicineBoxes = medicineBoxes
        self.medicationPlans = medicationPlans
        self.onMedicineBoxesChanged = onMedicineBoxesChanged
        self.onMedicineBoxAdded = onMedicineBoxAdded
        self.onCancel = onCancel
        self.onDone = onDone
        self.embedInNavigationView = embedInNavigationView
        _selections = State(initialValue: context.initialSelections)
        _doseEdits = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: context.doses.map { ($0.id, MedicationExecutionDoseEdit.from(dose: $0)) }
            )
        )
    }

    private var canSubmit: Bool {
        selections.isEmpty == false && isSaving == false
    }

    private var showsMedicineBoxLogLink: Bool {
        context.source == .medicationPlans
            && memberID != nil
            && homeDependencies != nil
    }

    private var showsMedicineCabinetAdd: Bool {
        context.source == .medicineBox
            && memberID != nil
            && homeDependencies != nil
    }

    var body: some View {
        Group {
            if embedInNavigationView {
                NavigationView {
                    sheetContent
                }
            } else {
                sheetContent
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selections)
        .sheet(item: $doseDetailRoute) { route in
            if let dose = context.doses.first(where: { $0.id == route.id }),
               let editBinding = binding(for: route.id) {
                MedicationExecutionDoseDetailSheet(
                    dose: dose,
                    dayStart: context.date,
                    edit: editBinding,
                    onCancel: { doseDetailRoute = nil },
                    onConfirm: { doseDetailRoute = nil }
                )
            }
        }
    }

    private var sheetContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                if context.doses.isEmpty {
                    Text(emptyStateText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    doseList
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                leadingToolbarButton
            }

            if showsMedicineBoxLogLink, let memberID, let homeDependencies {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        MedicationExecutionLogSheet(
                            context: medicineBoxLogContext,
                            isSaving: isSaving,
                            fileTransferService: fileTransferService,
                            memberID: memberID,
                            homeDependencies: homeDependencies,
                            medicineBoxes: medicineBoxes,
                            medicationPlans: medicationPlans,
                            onMedicineBoxesChanged: onMedicineBoxesChanged,
                            onMedicineBoxAdded: onMedicineBoxAdded,
                            onCancel: onCancel,
                            onDone: onDone,
                            embedInNavigationView: false
                        )
                    } label: {
                        medicineBoxToolbarLabel
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("home.medical.medication_execution.a11y.open_medicine_box_log"))
                }
            }

            if showsMedicineCabinetAdd, let memberID, let homeDependencies {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        FamilyMedicineCabinetPage(
                            entryMemberID: memberID,
                            mode: .personal,
                            initialMedicineBoxes: medicineBoxes,
                            dependencies: homeDependencies,
                            onMedicineBoxesChanged: onMedicineBoxesChanged,
                            onBoxCreated: { _ in
                                onMedicineBoxAdded()
                            }
                        )
                    } label: {
                        medicineBoxToolbarLabel
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("home.medical.medication_execution.a11y.add_medicine_box"))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                onDone(
                    MedicationExecutionLogSubmission(
                        selections: selections,
                        edits: doseEdits,
                        doses: resolvedDoses()
                    )
                )
            } label: {
                Text(L10n.text("common.done"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(
                        canSubmit ? Color(uiColor: .systemBlue) : Color(uiColor: .systemGray3),
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(canSubmit == false)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(.regularMaterial)
        }
    }

    @ViewBuilder
    private var leadingToolbarButton: some View {
        if embedInNavigationView {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .imageScale(.large)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("common.close"))
        } else {
            EmptyView()
        }
    }

    private var medicineBoxToolbarLabel: some View {
        Image(systemName: "pills.fill")
            .font(.title3.weight(.semibold))
            .imageScale(.large)
            .foregroundStyle(Color(uiColor: .systemBlue))
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle())
    }

    private var doseList: some View {
        VStack(spacing: 16) {
            ForEach(context.doses) { dose in
                MedicationExecutionLogDoseCard(
                    dose: dose,
                    edit: doseEdits[dose.id] ?? MedicationExecutionDoseEdit.from(dose: dose),
                    fileTransferService: fileTransferService,
                    selection: selections[dose.id],
                    onSelect: { status in
                        if selections[dose.id] == status {
                            selections.removeValue(forKey: dose.id)
                        } else {
                            selections[dose.id] = status
                        }
                        MedicationExecutionSupport.impact(style: .light)
                    },
                    onEditDetails: {
                        doseDetailRoute = MedicationExecutionDoseDetailRoute(id: dose.id)
                    }
                )
            }
        }
    }

    private var emptyStateText: String {
        switch context.source {
        case .medicationPlans:
            return L10n.text("home.medical.medication_execution.as_needed.empty")
        case .medicineBox:
            return L10n.text("home.medical.medication_execution.medicine_box.empty")
        }
    }

    private var medicineBoxLogContext: MedicationExecutionLogSheetContext {
        MedicationExecutionLogSheetContext(
            title: MedicationExecutionSupport.medicineBoxLogTitle(),
            date: context.date,
            doses: medicineBoxDoses,
            source: .medicineBox
        )
    }

    private var medicineBoxDoses: [MedicationExecutionDose] {
        guard let memberID else { return [] }
        return medicineBoxes
            .sorted {
                $0.medicineName.localizedCaseInsensitiveCompare($1.medicineName) == .orderedAscending
            }
            .enumerated()
            .map { index, box in
                MedicationExecutionPlanner.asNeededDose(
                    from: box,
                    plans: medicationPlans,
                    memberID: memberID,
                    date: context.date,
                    sequence: index + 1,
                    calendar: calendar
                )
            }
    }

    private func resolvedDoses() -> [MedicationExecutionDose] {
        context.doses.map { dose in
            guard let edit = doseEdits[dose.id] else { return dose }
            return MedicationExecutionDose(
                id: dose.id,
                plan: dose.plan,
                scheduledAt: edit.scheduledAt,
                plannedDose: edit.plannedDose,
                doseSequence: dose.doseSequence,
                record: dose.record,
                imageAttachment: dose.imageAttachment
            )
        }
    }

    private func binding(for doseID: MedicationExecutionDose.ID) -> Binding<MedicationExecutionDoseEdit>? {
        guard doseEdits[doseID] != nil else { return nil }
        return Binding(
            get: { doseEdits[doseID]! },
            set: { doseEdits[doseID] = $0 }
        )
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(MedicationExecutionSupport.logSheetDateTitle(context.date))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(context.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if context.doses.isEmpty == false {
                Text(L10n.format("home.medical.medication_execution.dose_count", context.doses.count))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MedicationExecutionDoseDetailRoute: Identifiable {
    let id: MedicationExecutionDose.ID
}

struct MedicationExecutionLogDoseCard: View {
    let dose: MedicationExecutionDose
    let edit: MedicationExecutionDoseEdit
    let fileTransferService: FileTransferService
    let selection: MedicationDoseLogStatus?
    let onSelect: (MedicationDoseLogStatus) -> Void
    let onEditDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                MedicationImageGlyph(
                    seed: dose.plan.id,
                    attachment: dose.imageAttachment,
                    fileTransferService: fileTransferService
                )
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dose.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(dose.specificationText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Button(action: onEditDetails) {
                        Label {
                            Text(dose.instructionText(edit: edit))
                        } icon: {
                            Image(systemName: "chevron.right")
                                .imageScale(.small)
                        }
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .systemBlue))
                        .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(L10n.text("home.medical.medication_execution.detail.open"))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                statusButton(.skipped)
                statusButton(.taken)
            }
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func statusButton(_ status: MedicationDoseLogStatus) -> some View {
        Button {
            onSelect(status)
        } label: {
            Label(status.title, systemImage: selection == status ? status.symbolName : "")
                .font(.headline.weight(.semibold))
                .foregroundStyle(selection == status ? .white : Color(uiColor: .systemBlue))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(
                    selection == status ? Color(uiColor: .systemBlue) : Color(uiColor: .systemBlue).opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}
