import SwiftUI

/// 家庭药箱模式顶部人员筛选胶囊条
struct MedicineBoxMemberFilterBar: View {
    let options: [(FamilyMedicineCabinetViewModel.MemberFilter, String)]
    let selectedFilter: FamilyMedicineCabinetViewModel.MemberFilter
    let onSelect: (FamilyMedicineCabinetViewModel.MemberFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { filter, title in
                    Button {
                        onSelect(filter)
                    } label: {
                        Text(title)
                            .font(.subheadline.weight(selectedFilter == filter ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    selectedFilter == filter
                                        ? Color(uiColor: .systemPurple).opacity(0.15)
                                        : Color(uiColor: .secondarySystemGroupedBackground)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
