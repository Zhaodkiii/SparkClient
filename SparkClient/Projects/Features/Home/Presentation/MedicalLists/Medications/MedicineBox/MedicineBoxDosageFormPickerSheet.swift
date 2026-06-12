import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MedicineBoxDosageFormPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    var body: some View {
        CompatibleNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    MedicineBoxDosageFormHeaderIcon()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)

                    Text(L10n.text("medical_record.medicine_box.dosage_form_sheet.title"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 20)

                    dosageFormSection(
                        title: L10n.text("medical_record.medicine_box.dosage_form_sheet.common_section"),
                        items: MedicineBoxDosageFormCatalog.commonForms
                    )
                    dosageFormSection(
                        title: L10n.text("medical_record.medicine_box.dosage_form_sheet.more_section"),
                        items: MedicineBoxDosageFormCatalog.moreForms
                    )
                }
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.text("common.cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func dosageFormSection(title: String, items: [MedicineBoxDosageFormCatalog.Item]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Section(L10n.text(title)) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.storedValue) { index, item in
                        Button {
                            select(item)
                        } label: {
                            HStack(spacing: 12) {
                                Text(item.displayName)
                                    .font(.title3)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if normalizedSelection == item.storedValue {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < items.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .font(.title3.bold())
            .foregroundColor(.primary)
            .padding(.horizontal, 20)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: normalizedSelection)
    }

    private func select(_ item: MedicineBoxDosageFormCatalog.Item) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selection = item.storedValue
        }
        dismiss()
    }

    private var normalizedSelection: String {
        selection.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MedicineBoxDosageFormCatalog {
    struct Item: Hashable {
        let storedValue: String
        let localizationKey: String
        let fallback: String

        var displayName: String {
            L10n.text(localizationKey, fallback: fallback)
        }
    }

    static let commonForms: [Item] = [
        item("胶囊", key: "capsule", fallback: "胶囊"),
        item("药片", key: "tablet", fallback: "药片"),
        item("液体", key: "liquid", fallback: "液体"),
        item("外用", key: "topical", fallback: "外用")
    ]

    static let moreForms: [Item] = [
        item("乳液", key: "lotion", fallback: "乳液"),
        item("乳霜", key: "cream", fallback: "乳霜"),
        item("凝胶", key: "gel", fallback: "凝胶"),
        item("吸入剂", key: "inhaler", fallback: "吸入剂"),
        item("喷剂", key: "spray", fallback: "喷剂"),
        item("栓剂", key: "suppository", fallback: "栓剂"),
        item("泡沫", key: "foam", fallback: "泡沫"),
        item("注射", key: "injection", fallback: "注射"),
        item("滴剂", key: "drops", fallback: "滴剂"),
        item("粉末", key: "powder", fallback: "粉末"),
        item("设备", key: "device", fallback: "设备"),
        item("贴剂", key: "patch", fallback: "贴剂"),
        item("软膏", key: "ointment", fallback: "软膏")
    ]

    static func displayString(stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        return allForms.first { $0.storedValue == trimmed }?.displayName ?? trimmed
    }

    static func storedValue(fromAny raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        if let item = allForms.first(where: { $0.storedValue == trimmed || $0.displayName == trimmed }) {
            return item.storedValue
        }
        return trimmed
    }

    private static var allForms: [Item] {
        commonForms + moreForms
    }

    private static func item(_ storedValue: String, key: String, fallback: String) -> Item {
        Item(
            storedValue: storedValue,
            localizationKey: "medical_record.medicine_box.dosage_form.\(key)",
            fallback: fallback
        )
    }
}

struct MedicineBoxDosageFormHeaderIcon: View {
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "pills.fill")
                .font(.largeTitle)
                .symbolRenderingMode(.multicolor)

            Image(systemName: "cross.case.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemTeal))

            Image(systemName: "drop.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemBlue))

            Image(systemName: "bandage.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemPink))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
