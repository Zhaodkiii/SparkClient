import SwiftUI

/// 药箱顶部药品类型筛选胶囊条（家庭/个人模式共用）
struct MedicineBoxTypeTabBar: View {
    let typeOptions: [String]
    let selectedTypeTab: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                typeTabButton(title: L10n.text("common.all"), storedValue: "")
                ForEach(MedicineBoxTypeCatalog.displayOptions(for: typeOptions), id: \.self) { display in
                    typeTabButton(
                        title: display,
                        storedValue: MedicineBoxTypeCatalog.storedValue(fromDisplay: display)
                    )
                }
            }
        }
    }

    private func typeTabButton(title: String, storedValue: String) -> some View {
        let selected = MedicineBoxTypeCatalog.storedValue(fromAny: selectedTypeTab.nilIfBlank) == storedValue
        return Button {
            onSelect(storedValue)
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        selected
                            ? Color(uiColor: .systemBlue).opacity(0.15)
                            : Color(uiColor: .secondarySystemGroupedBackground)
                    )
                )
        }
        .buttonStyle(.plain)
    }
}
