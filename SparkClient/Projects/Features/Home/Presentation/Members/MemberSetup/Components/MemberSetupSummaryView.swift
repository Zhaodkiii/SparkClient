import SwiftUI

struct MemberSetupSummaryView: View {
    let member: Member
    let selectedCount: Int
    let completedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(member.name)
                        .font(.headline)
                    Text(MemberRelationshipCatalog.displayTitle(for: member.relationship))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                MemberModuleCompletionBadge(isCompleted: completedCount == selectedCount && selectedCount > 0)
            }

            Text("已选择 \(selectedCount) 个模块，已完成 \(completedCount) 个")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }
}
