import SwiftUI

struct TaskCardCell: View {
    let card: TaskCard
    @ObservedObject var memberContextStore: MemberContextStore
    let onAction: (TaskCard.Action) -> Void
    var isLoading: Bool = false

    private var members: [Member] {
        memberContextStore.context.members
    }

    private var canOperate: Bool {
        card.status == .pending && isLoading == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(typeTagText)
                    .font(.caption.bold())
                    .foregroundStyle(typeTagColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(typeTagColor.opacity(0.12), in: Capsule())

                Spacer()

                memberMenu
            }

            HStack(spacing: 6) {
                Text(statusText)
                    .font(.caption2.bold())
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.14), in: Capsule())
                Spacer()
                Text(cardTimeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(displayTitle)
                .font(.headline)
                .foregroundStyle(.primary)

            if card.description.isEmpty == false {
                Text(card.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if card.status == .pending {
                HStack(spacing: 12) {
                    Button {
                        onAction(.confirm(card))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(NSLocalizedString("task.card.create", comment: "创建任务"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(canOperate == false)

                    Button(role: .destructive) {
                        onAction(.ignore(card))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle")
                            Text(NSLocalizedString("task.card.ignore", comment: "忽略"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(canOperate == false)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
        )
    }

    private var typeTagText: String {
        card.type.displayName
    }

    private var memberMenu: some View {
        MemberProfileBindingMenu(
            memberContextStore: memberContextStore,
            selectedMemberID: card.member,
            onSelect: { memberID in
                onAction(.setMember(card, memberID))
            }
        ) {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                    .imageScale(.small)
                Text(memberName(for: card.member))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(card.member == nil ? .secondary : Color(uiColor: .systemGreen))
        }
    }

    private func memberName(for memberID: Int?) -> String {
        guard let memberID else {
            return L10n.text("medical.upload.member.not_selected")
        }
        return members.first(where: { $0.id == memberID })?.name
            ?? L10n.text("chat.composer.member_profile.unknown")
    }

    private var displayTitle: String {
        let text = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? NSLocalizedString("task.card.default_title", comment: "AI 任务建议") : text
    }

    private var typeTagColor: Color {
        switch card.type {
        case .medical: return .red
        case .exercise: return .green
        case .diet: return .orange
        }
    }

    private var statusText: String {
        switch card.status {
        case .pending:
            return NSLocalizedString("task.card.status.pending", comment: "待确认")
        case .confirmed:
            return NSLocalizedString("task.card.status.confirmed", comment: "已创建")
        case .ignored:
            return NSLocalizedString("task.card.status.ignored", comment: "已忽略")
        case .expired:
            return NSLocalizedString("task.card.status.expired", comment: "已过期")
        }
    }

    private var statusColor: Color {
        switch card.status {
        case .pending: return .orange
        case .confirmed: return .green
        case .ignored: return .gray
        case .expired: return .red
        }
    }

    private var cardTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        if let due = card.dueTime {
            return formatter.string(from: due)
        }
        if let start = card.startTime {
            return formatter.string(from: start)
        }
        return NSLocalizedString("task.time.unspecified", comment: "未设置时间")
    }
}
