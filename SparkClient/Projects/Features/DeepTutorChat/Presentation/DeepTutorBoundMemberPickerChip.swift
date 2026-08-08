import SwiftUI

struct DeepTutorBoundMemberPickerChip: View {
    let displayModel: DeepTutorBoundMemberDisplayModel
    let members: [Member]
    let isDisabled: Bool
    let onSelect: (Int?) -> Void

    private var tint: Color {
        switch displayModel.state {
        case .unbound:
            return Color.secondary
        case .bound:
            return Color(uiColor: .systemGreen)
        case .missing:
            return Color.orange
        }
    }

    private var shouldDisable: Bool {
        if isDisabled { return true }
        if members.isEmpty {
            if case .unbound = displayModel.state {
                return true
            }
        }
        return false
    }

    var body: some View {
        Menu {
            if members.isEmpty {
                Button {
                    onSelect(nil)
                } label: {
                    Label("暂无成员", systemImage: "person.crop.circle")
                }
                .disabled(true)
            } else {
                ForEach(members) { member in
                    Button {
                        onSelect(member.id)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name)
                                if member.relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                                    Text(member.relationship)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            if case let .bound(memberID, _, _) = displayModel.state, memberID == member.id {
                                Image(systemName: "checkmark.circle.fill")
                            } else {
                                Image(systemName: "person.crop.circle")
                            }
                        }
                    }
                }
            }

            if case .unbound = displayModel.state {
                EmptyView()
            } else {
                Divider()
                Button(role: .destructive) {
                    onSelect(nil)
                } label: {
                    Label("解绑成员", systemImage: "person.crop.circle.badge.minus")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: displayModel.iconName)
                    .font(.system(size: 12, weight: .semibold))
                Text(displayModel.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            )
        }
        .disabled(shouldDisable)
        .accessibilityLabel(displayModel.accessibilityLabel)
        .opacity(shouldDisable ? 0.58 : 1)
    }
}
