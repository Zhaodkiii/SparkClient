import SwiftUI

/// 成员选择底部弹窗：用于「切换绑定成员」和「添加设备时选择成员」。
struct MemberSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let members: [Member]
    /// 需要标记「已绑定」的成员 ID。
    let selectedMemberID: Int?
    let onSelect: (Member) -> Void

    var body: some View {
        NavigationStack {
            List(members) { member in
                Button {
                    onSelect(member)
                } label: {
                    memberRow(member)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func memberRow(_ member: Member) -> some View {
        HStack(spacing: 12) {
            MemberAvatarView(name: member.name, avatarUrl: member.avatarUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(member.id == selectedMemberID ? Color.accentColor : .primary)
                Text(MemberRelationshipCatalog.displayTitle(for: member.relationship))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if member.id == selectedMemberID {
                Text(L10n.text("device.switch.bound_tag", fallback: "已绑定"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 成员头像组件（有 URL 时加载网络图，否则显示首字符）。
struct MemberAvatarView: View {
    let name: String
    let avatarUrl: String
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            .frame(width: size, height: size)
            .overlay {
                if let first = name.first {
                    Text(String(first))
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.secondary)
                }
            }
    }
}