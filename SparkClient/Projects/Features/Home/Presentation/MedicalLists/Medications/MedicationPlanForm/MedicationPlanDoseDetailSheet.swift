import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MedicationPlanDoseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
//    @Binding var doseValue: String
    @Binding var doseUnit: String
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]

    @State private var tempDoseValue = ""
    @State private var tempDoseUnit = ""
    @FocusState private var doseValueFocused: Bool

    private static let selectedChip = Color(red: 79 / 255, green: 70 / 255, blue: 229 / 255)
    private static let sheetHeaderChromeHeight: CGFloat = 72
    private static let sheetFooterChromeHeight: CGFloat = 88

    private var doseUnitLabels: [String] {
        MedicineSpecificationCatalog.doseUnitMenuOptions(boxes: specOptionBoxes)
    }

    private var prefersEnglish: Bool {
        SparkFormCatalogMenuLocale.prefersEnglish
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    }

    private var trimmedTempDoseUnit: String {
        tempDoseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        CompatibleNavigationContainer {
            AdaptiveToolSheetScrollView(
                bottomContentPadding: 12,
                extraChromeHeight: Self.sheetHeaderChromeHeight + Self.sheetFooterChromeHeight
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    sheetFieldBlock(title: L10n.text("medical_record.medicine_box.spec.dose_value")) {
                        HStack(spacing: prefersEnglish ? 6 : 0) {
                            TextField("5", text: doseValueBinding)
                                .textFieldStyle(.plain)
                                .focused($doseValueFocused)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)

                            if trimmedTempDoseUnit.isEmpty == false {
                                Text(MedicineSpecificationCatalog.displayUnit(stored: trimmedTempDoseUnit, prefersEnglish: prefersEnglish))
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.secondary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    unitChipBlock(
                        title: L10n.text("medical_record.medicine_box.spec.dose_unit"),
                        labels: doseUnitLabels,
                        isSelected: { label in
                            MedicineSpecificationCatalog.storedDoseUnit(fromDisplay: label)
                            == MedicineSpecificationCatalog.storedDoseUnit(fromAny: tempDoseUnit)
                        },
                        onSelect: { label in
                            tempDoseUnit = MedicineSpecificationCatalog.storedDoseUnit(fromDisplay: label)
                        }
                    )
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .navigationTitle(L10n.text("medication_plan.form.single_dose_value_sheet_title", fallback: "单次剂量数值"))
            .navigationBarTitleDisplayMode(.inline)
            .sparkKeyboardDoneToolbar {
                SparkKeyboardDismiss.endEditing()
            }
            .sparkFormBottomBar(
                canSubmit: true,
                cancelTitle: L10n.text("common.cancel"),
                saveTitle: L10n.text("common.done"),
                saveSystemImage: "checkmark.circle.fill",
                onCancel: {
                    dismiss()
                },
                onSave: {
                    doseUnit = tempDoseValue + tempDoseUnit
                    dismiss()
                }
            )
        }
        .ignoresSafeArea()
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            let parts = MedicineSpecification.doseValueAndStoredUnit(fromBackendDoseUnitField: doseUnit)
            tempDoseValue = parts.value
            tempDoseUnit = parts.unit
        }
    }

    private var doseValueBinding: Binding<String> {
        Binding(
            get: { tempDoseValue },
            set: { tempDoseValue = $0 }
        )
    }

    private func sheetFieldBlock(title: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            field()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator).opacity(0.35))
        }
    }

    private func unitChipBlock(
        title: String,
        labels: [String],
        isSelected: @escaping (String) -> Bool,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .padding(.top, 16)

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(labels, id: \.self) { label in
                    let selected = isSelected(label)
                    Button {
                        onSelect(label)
                    } label: {
                        Text(label)
                            .font(.system(size: 14))
                            .foregroundColor(selected ? .white : Color.primary.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)
                            .background(selected ? Self.selectedChip : Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator).opacity(0.35))
        }
    }
}
