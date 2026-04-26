import SwiftUI

struct ChatPendingMemberToolCardView: View {
    let card: PendingMemberToolCard
    @ObservedObject var memberContextStore: MemberContextStore
    let onSelectMember: (PendingMemberToolCard, Int?) -> Void

    private var members: [Member] {
        memberContextStore.context.members
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(Color(uiColor: .systemGreen))
                Text(L10n.text("chat.pending_member_tool.title"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if card.selectedMemberID != nil || card.status == .completed {
                    selectedMemberBadge
                } else {
                    memberMenu
                }
            }

            Text(card.resultText ?? L10n.text("chat.pending_member_tool.message"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if card.status == .running {
                ProgressView()
                    .scaleEffect(0.85)
            }
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private var memberMenu: some View {
        MemberProfileBindingMenu(
            memberContextStore: memberContextStore,
            selectedMemberID: card.selectedMemberID,
            onSelect: { memberID in
                onSelectMember(card, memberID)
            }
        ) {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                    .imageScale(.small)
                Text(memberName(for: card.selectedMemberID))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(card.selectedMemberID == nil ? .secondary : Color(uiColor: .systemGreen))
        }
    }

    private var selectedMemberBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .imageScale(.small)
            Text(memberName(for: card.selectedMemberID))
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color(uiColor: .systemGreen))
    }

    private func memberName(for memberID: Int?) -> String {
        guard let memberID else {
            return L10n.text("medical.upload.member.not_selected")
        }
        return members.first(where: { $0.id == memberID })?.name
            ?? L10n.text("chat.composer.member_profile.unknown")
    }
}
