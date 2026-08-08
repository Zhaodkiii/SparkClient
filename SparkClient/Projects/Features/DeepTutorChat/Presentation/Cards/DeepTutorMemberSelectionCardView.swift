import SwiftUI

struct DeepTutorMemberSelectionCardView: View {
    let payload: DeepTutorMemberSelectionBlockPayload
    let members: [Member]
    let onSelectMember: (Int) -> Void

    @State private var optimisticSelectedMemberID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if payload.isResolved || optimisticSelectedMemberID != nil {
                resolvedSummary
            } else if members.isEmpty {
                emptyState
            } else {
                interactiveContent
            }
        }
        .padding(16)
        .background(DeepTutorPalette.cardBackground, in: cardShape)
        .overlay {
            cardShape.strokeBorder(DeepTutorPalette.borderColor, lineWidth: 1)
        }
        .deepTutorAskUserCardShadow()
        .padding(.top, 12)
        .onAppear {
            DeepTutorChatLog.memberSelectionCardRendered(
                blockID: UUID(uuidString: payload.toolCallID) ?? UUID(),
                status: payload.status.rawValue,
                selectedMemberID: payload.selectedMemberID
            )
        }
    }

    private var interactiveContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader

            Text(payload.reason)
                .font(.system(size: DeepTutorPalette.bodyFontSize))
                .foregroundStyle(.primary)
                .padding(.top, 12)

            VStack(spacing: 10) {
                ForEach(members) { member in
                    memberRow(member)
                }
            }
            .padding(.top, 12)

            Text("未选择成员将无法继续使用该工具。")
                .font(.system(size: DeepTutorPalette.askUserFooterFontSize))
                .foregroundStyle(DeepTutorPalette.traceMutedText)
                .padding(.top, 12)
        }
    }

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: DeepTutorPalette.askUserBadgeSize, height: DeepTutorPalette.askUserBadgeSize)

            VStack(alignment: .leading, spacing: 2) {
                Text("请选择成员")
                    .font(.system(size: DeepTutorPalette.askUserHeaderFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                Text("该工具需要确认要查询哪位家庭成员。")
                    .font(.system(size: DeepTutorPalette.askUserSubtitleFontSize))
                    .foregroundStyle(DeepTutorPalette.traceMutedText)
            }
        }
    }

    private func memberRow(_ member: Member) -> some View {
        let isSelected = effectiveSelectedMemberID == member.id
        let isDisabled = payload.status == .running || payload.status == .completed || optimisticSelectedMemberID != nil

        return Button {
            guard isDisabled == false else { return }
            optimisticSelectedMemberID = member.id
            onSelectMember(member.id)
        } label: {
            HStack(spacing: 12) {
                memberAvatar(member)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.system(size: DeepTutorPalette.askUserOptionTitleFontSize, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(memberSubtitle(member))
                        .font(.system(size: DeepTutorPalette.askUserOptionDescriptionFontSize))
                        .foregroundStyle(DeepTutorPalette.traceMutedText)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : DeepTutorPalette.cardBackground,
                in: optionRowShape
            )
            .overlay {
                optionRowShape.strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.5) : DeepTutorPalette.borderColor,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func memberAvatar(_ member: Member) -> some View {
        Text(String(member.name.prefix(1)))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 36, height: 36)
            .background(Color.accentColor.opacity(0.12), in: Circle())
    }

    private func memberSubtitle(_ member: Member) -> String {
        var parts: [String] = []
        if member.relationship.isEmpty == false {
            parts.append(member.relationship)
        }
        if let birthDate = member.birthDate {
            let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
            if years > 0 {
                parts.append("\(years)岁")
            }
        }
        if member.gender != "unknown" {
            parts.append(member.gender)
        }
        return parts.joined(separator: " · ")
    }

    private var resolvedSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(payload.isResolved ? "已选择成员" : "已选择成员，正在继续", systemImage: "checkmark.circle.fill")
                .font(.system(size: DeepTutorPalette.askUserHeaderFontSize, weight: .semibold))
                .foregroundStyle(.green)
            if let name = payload.selectedMemberName ?? members.first(where: { $0.id == effectiveSelectedMemberID })?.name {
                Text("已选择：\(name)")
                    .font(.system(size: DeepTutorPalette.bodyFontSize, weight: .medium))
                    .foregroundStyle(.primary)
            }
            Text(payload.resultText ?? "AI 将继续使用该成员完成本次查询。")
                .font(.system(size: DeepTutorPalette.askUserFooterFontSize))
                .foregroundStyle(DeepTutorPalette.traceMutedText)
        }
    }

    private var effectiveSelectedMemberID: Int? {
        payload.selectedMemberID ?? optimisticSelectedMemberID
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader
            Text("暂无可选择的成员档案")
                .font(.system(size: DeepTutorPalette.bodyFontSize, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.top, 12)
            Text("请先创建家庭成员后，再继续使用健康数据工具。")
                .font(.system(size: DeepTutorPalette.askUserFooterFontSize))
                .foregroundStyle(DeepTutorPalette.traceMutedText)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DeepTutorPalette.askUserCardCornerRadius, style: .continuous)
    }

    private var optionRowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DeepTutorPalette.askUserOptionCornerRadius, style: .continuous)
    }
}
