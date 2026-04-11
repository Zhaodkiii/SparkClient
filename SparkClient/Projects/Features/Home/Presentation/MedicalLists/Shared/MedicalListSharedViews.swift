import SwiftUI

/// 列表空态行。
struct MedicalListEmptyRow: View {
    var body: some View {
        Text(L10n.text("home.medical.list.empty"))
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
    }
}

extension View {
    /// 统一四类医疗列表卡片在 `List` 中的边距与背景样式。
    func medicalListCardRowStyle() -> some View {
        listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
    }
}
