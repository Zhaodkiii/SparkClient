import SwiftUI

struct MedicineBoxSpecificationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var specification: MedicineSpecification
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]

    @State private var tempSpec: MedicineSpecification
    @FocusState private var doseValueFocused: Bool
    @FocusState private var packageCountFocused: Bool

    private static let selectedChip = Color(red: 79 / 255, green: 70 / 255, blue: 229 / 255)
    private static let sheetHeaderChromeHeight: CGFloat = 72
    private static let sheetFooterChromeHeight: CGFloat = 88

    init(
        specification: Binding<MedicineSpecification>,
        specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    ) {
        _specification = specification
        self.specOptionBoxes = specOptionBoxes
        _tempSpec = State(initialValue: specification.wrappedValue)
    }

    private var doseUnitLabels: [String] {
        MedicineSpecificationCatalog.doseUnitMenuOptions(boxes: specOptionBoxes)
    }

    private var innerUnitLabels: [String] {
        MedicineSpecificationCatalog.innerPackageMenuOptions(boxes: specOptionBoxes)
    }

    private var outerUnitLabels: [String] {
        MedicineSpecificationCatalog.outerPackageMenuOptions(boxes: specOptionBoxes)
    }

    private var prefersEnglish: Bool {
        SparkFormCatalogMenuLocale.prefersEnglish
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    }

    private var previewLine: String {
        let t = tempSpec.displayString(prefersEnglish: prefersEnglish)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? L10n.text("medical_record.medicine_box.spec.preview_empty") : t
    }

    private var trimmedTempDoseUnit: String {
        tempSpec.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        CompatibleNavigationContainer {
            AdaptiveToolSheetScrollView(
                bottomContentPadding: 12,
                extraChromeHeight: Self.sheetHeaderChromeHeight + Self.sheetFooterChromeHeight
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    legacyFreeformBlock
                    
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
                            == MedicineSpecificationCatalog.storedDoseUnit(fromAny: tempSpec.doseUnit)
                        },
                        onSelect: { label in
                            tempSpec.rawLegacyStrength = nil
                            let doseUnit = MedicineSpecificationCatalog.storedDoseUnit(fromDisplay: label)
                            tempSpec.doseUnit = doseUnit
                        }
                    )
                    
                    sheetFieldBlock(title: L10n.text("medical_record.medicine_box.spec.package_count")) {
                        TextField("28", text: packageCountBinding)
                            .textFieldStyle(.plain)
                            .focused($packageCountFocused)
                            .keyboardType(.numberPad)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    
                    unitChipBlock(
                        title: L10n.text("medical_record.medicine_box.spec.package_unit"),
                        labels: innerUnitLabels,
                        isSelected: { label in
                            MedicineSpecificationCatalog.storedInnerPackage(fromDisplay: label)
                            == MedicineSpecificationCatalog.storedInnerPackage(fromAny: tempSpec.packageUnit)
                        },
                        onSelect: { label in
                            tempSpec.rawLegacyStrength = nil
                            tempSpec.packageUnit = MedicineSpecificationCatalog.storedInnerPackage(fromDisplay: label)
                        }
                    )
                    
                    unitChipBlock(
                        title: L10n.text("medical_record.medicine_box.spec.outer_unit"),
                        labels: outerUnitLabels,
                        isSelected: { label in
                            MedicineSpecificationCatalog.storedOuterPackage(fromDisplay: label)
                            == MedicineSpecificationCatalog.storedOuterPackage(fromAny: tempSpec.outerPackageUnit)
                        },
                        onSelect: { label in
                            tempSpec.rawLegacyStrength = nil
                            tempSpec.outerPackageUnit = MedicineSpecificationCatalog.storedOuterPackage(fromDisplay: label)
                        }
                    )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("medical_record.medicine_box.spec.preview"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Text(previewLine)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .navigationTitle(L10n.text("medical_record.medicine_box.strength_sheet.title"))
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
                    specification = tempSpec
                    dismiss()
                }
            )
        }
        .ignoresSafeArea()
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            tempSpec = specification
        }
    }

    @ViewBuilder
    private var legacyFreeformBlock: some View {
        if tempSpec.rawLegacyStrength != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("medical_record.medicine_box.strength_sheet.custom_section"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                TextField(
                    L10n.text("medical_record.medicine_box.strength_sheet.placeholder"),
                    text: Binding(
                        get: { tempSpec.rawLegacyStrength ?? "" },
                        set: { newValue in
                            let t = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            tempSpec.rawLegacyStrength = t.isEmpty ? nil : t
                        }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(uiColor: .separator).opacity(0.35))
            }
        }
    }

    private var doseValueBinding: Binding<String> {
        Binding(
            get: { tempSpec.doseValue },
            set: {
                tempSpec.doseValue = $0
                tempSpec.rawLegacyStrength = nil
            }
        )
    }

    private var packageCountBinding: Binding<String> {
        Binding(
            get: { tempSpec.packageCount },
            set: {
                tempSpec.packageCount = $0
                tempSpec.rawLegacyStrength = nil
            }
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
