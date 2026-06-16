import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MedicationPlanMedicineBoxPickerPage: View {
    let memberID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let onMedicineBoxSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    let onSelect: (SparkMedicalSyncAPI.RemoteMedicineBox?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var selectedMedicineBoxID: Int?
    @State private var sheetDestination: MedicineBoxSheetDestination?

    init(
        memberID: Int,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        selectedMedicineBoxID: Int?,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        onMedicineBoxSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onSelect: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox?) -> Void
    ) {
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.onMedicineBoxSaved = onMedicineBoxSaved
        self.onSelect = onSelect
        _medicineBoxes = State(initialValue: medicineBoxes)
        _selectedMedicineBoxID = State(initialValue: selectedMedicineBoxID)
    }

    private var sortedBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] {
        medicineBoxes.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var medicineTypeOptions: [String] {
        MedicineBoxTypeCatalog.options(in: medicineBoxes)
    }

    private func medicineBoxStrengthListSubtitle(_ strength: String) -> String? {
        let raw = strength.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isEmpty == false else { return nil }
        let spec = MedicineSpecification.parse(fromAPIStrength: raw)
        if spec.hasStructuredContent {
            return spec.displayString(prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish)
        }
        return raw
    }

    var body: some View {
        List {
            Section {
                Button {
                    selectedMedicineBoxID = nil
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Label(L10n.text("medication_plan.medicine_box_picker.none", fallback: "不关联药箱药品"), systemImage: "link.badge.minus")
                        Spacer()
                        if selectedMedicineBoxID == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }

            Section(L10n.text("medication_plan.medicine_box_picker.section.medicines", fallback: "药箱药品")) {
                if sortedBoxes.isEmpty {
                    Text(L10n.text("medication_plan.medicine_box_picker.empty", fallback: "暂无药箱药品"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedBoxes, id: \.id) { box in
                        HStack(spacing: 12) {
                            Button {
                                selectedMedicineBoxID = box.id
                                onSelect(box)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(box.medicineName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed", fallback: "未命名药品"))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text([
                                            medicineBoxStrengthListSubtitle(box.strength),
                                            box.dosageForm.nilIfBlank,
                                            stockText(box)
                                        ].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if selectedMedicineBoxID == box.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                sheetDestination = .serverEdit(box)
                            } label: {
                                Image(systemName: "pencil.circle")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.text("medication_plan.medicine_box_picker.a11y.edit_medicine", fallback: "编辑药品"))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(L10n.text("medication_plan.medicine_box_picker.title", fallback: "选择药品"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sheetDestination = .create
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel(L10n.text("home.medical.medicine_box.add_a11y", fallback: "新增药品"))
            }
        }
        .sheet(item: $sheetDestination) { destination in
            MedicineBoxFormView(
                mode: destination.formMode,
                entryMemberID: memberID,
                defaultBindingMemberID: memberID,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                typeOptions: medicineTypeOptions,
                specOptionBoxes: medicineBoxes,
                onServerSaved: upsertMedicineBox
            )
        }
    }

    private func upsertMedicineBox(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = medicineBoxes.firstIndex(where: { $0.id == box.id }) {
            medicineBoxes[index] = box
        } else {
            medicineBoxes.insert(box, at: 0)
        }
        onMedicineBoxSaved(box)
        selectedMedicineBoxID = box.id
        onSelect(box)
        sheetDestination = nil
    }
}
