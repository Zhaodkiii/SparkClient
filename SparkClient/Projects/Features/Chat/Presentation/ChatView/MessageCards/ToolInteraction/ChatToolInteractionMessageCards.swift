import SwiftUI

private enum ChatToolInteractionCardStyle {
    static let cardCornerRadius: CGFloat = 18
    static let optionCornerRadius: CGFloat = 12
    static let badgeSize: CGFloat = 24
    static let cardPadding: CGFloat = 16
    static let headerFontSize: CGFloat = 13
    static let subtitleFontSize: CGFloat = 11
    static let bodyFontSize: CGFloat = 14
    static let optionTitleFontSize: CGFloat = 13.5
    static let optionDescriptionFontSize: CGFloat = 11.5
    static let footerFontSize: CGFloat = 11.5

    static var cardBackground: Color { Color(.secondarySystemBackground) }
    static var borderColor: Color { Color.primary.opacity(0.08) }
    static var mutedText: Color { Color.secondary }
}

struct ChatToolQuestionMessageCardView: View {
    let card: ChatToolQuestionCard
    let onSubmit: (ChatToolQuestionCard, [ToolQuestionResponse]) -> Void

    @State private var selectedOptionIDs: [String: Set<String>] = [:]
    @State private var otherTextByQuestion: [String: String] = [:]

    private var isResolved: Bool {
        card.status != .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isResolved {
                resolvedSummary
            } else {
                interactiveContent
            }
        }
        .padding(ChatToolInteractionCardStyle.cardPadding)
        .background(ChatToolInteractionCardStyle.cardBackground, in: cardShape)
        .overlay {
            cardShape.strokeBorder(ChatToolInteractionCardStyle.borderColor, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
        .padding(.top, 8)
        .onAppear {
            if selectedOptionIDs.isEmpty, otherTextByQuestion.isEmpty {
                hydrateFromAnswers()
            }
        }
    }

    private var interactiveContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader

            ForEach(card.prompt.questions) { question in
                questionBlock(question)
            }

            footer
        }
    }

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("?")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.72))
                .frame(width: ChatToolInteractionCardStyle.badgeSize, height: ChatToolInteractionCardStyle.badgeSize)
                .background(Color.primary.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("请作答以继续")
                    .font(.system(size: ChatToolInteractionCardStyle.headerFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                Text("该工具需要你的补充选择。")
                    .font(.system(size: ChatToolInteractionCardStyle.subtitleFontSize))
                    .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
            }
        }
    }

    @ViewBuilder
    private func questionBlock(_ question: ToolQuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(question.question)
                .font(.system(size: ChatToolInteractionCardStyle.bodyFontSize, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.top, 12)

            VStack(spacing: 6) {
                ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                    optionRow(
                        question: question,
                        option: option,
                        letter: letter(for: index),
                        isSelected: selectedOptionIDs[question.id, default: []].contains(option.id)
                    )
                }

                if question.allowsOther {
                    TextField(
                        "输入自定义回复",
                        text: Binding(
                            get: { otherTextByQuestion[question.id, default: ""] },
                            set: { otherTextByQuestion[question.id] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: ChatToolInteractionCardStyle.optionTitleFontSize))
                    .padding(.top, 4)
                }
            }
            .padding(.top, 8)
        }
    }

    private func optionRow(
        question: ToolQuestionItem,
        option: ChatQuestionOption,
        letter: String,
        isSelected: Bool
    ) -> some View {
        Button {
            toggle(option.id, for: question)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                letterBadge(letter, isSelected: isSelected)
                Text(option.text)
                    .font(.system(size: ChatToolInteractionCardStyle.optionTitleFontSize))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ChatToolInteractionCardStyle.cardBackground, in: optionShape)
            .overlay {
                optionShape.strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.5) : ChatToolInteractionCardStyle.borderColor,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("提交后工具会继续执行。")
                .font(.system(size: ChatToolInteractionCardStyle.footerFontSize))
                .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("提交") {
                onSubmit(card, responses())
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ChatToolInteractionCardStyle.borderColor.opacity(0.6))
                .frame(height: 1)
        }
        .padding(.top, 12)
    }

    private var resolvedSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(resolvedTitle, systemImage: resolvedIcon)
                .font(.system(size: ChatToolInteractionCardStyle.headerFontSize, weight: .semibold))
                .foregroundStyle(resolvedColor)
            ForEach(resolvedAnswerTexts, id: \.self) { text in
                Text(text)
                    .font(.system(size: ChatToolInteractionCardStyle.bodyFontSize))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var resolvedTitle: String {
        switch card.status {
        case .submitted:
            return "已提交回答"
        case .cancelled:
            return "已取消回答"
        case .expired:
            return "本次等待已失效"
        case .pending:
            return "等待回答"
        }
    }

    private var resolvedIcon: String {
        card.status == .submitted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var resolvedColor: Color {
        card.status == .submitted ? .green : .secondary
    }

    private var resolvedAnswerTexts: [String] {
        let values = card.answers.map { response in
            answerText(for: response)
        }.filter { $0.isEmpty == false }
        if values.isEmpty == false { return values }
        return [card.resultText ?? "工具等待已经结束。"]
    }

    private func hydrateFromAnswers() {
        for answer in card.answers {
            selectedOptionIDs[answer.questionID] = Set(answer.selectedOptionIDs)
            if let otherText = answer.otherText {
                otherTextByQuestion[answer.questionID] = otherText
            }
        }
    }

    private func toggle(_ id: String, for question: ToolQuestionItem) {
        var ids = selectedOptionIDs[question.id] ?? []
        switch question.selectionMode {
        case .single:
            ids = [id]
        case .multiple:
            if ids.contains(id) {
                ids.remove(id)
            } else {
                ids.insert(id)
            }
        }
        selectedOptionIDs[question.id] = ids
    }

    private func responses() -> [ToolQuestionResponse] {
        card.prompt.questions.map { question in
            ToolQuestionResponse(
                questionID: question.id,
                selectedOptionIDs: Array(selectedOptionIDs[question.id] ?? []),
                otherText: nonEmpty(otherTextByQuestion[question.id])
            )
        }
    }

    private func answerText(for response: ToolQuestionResponse) -> String {
        guard let question = card.prompt.questions.first(where: { $0.id == response.questionID }) else {
            return response.otherText ?? ""
        }
        let selectedIDs = Set(response.selectedOptionIDs)
        var parts = question.options.filter { selectedIDs.contains($0.id) }.map(\.text)
        if let other = nonEmpty(response.otherText) {
            parts.append(other)
        }
        return parts.isEmpty ? "已跳过：\(question.question)" : "\(question.question)：\(parts.joined(separator: "，"))"
    }

    private func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func letter(for index: Int) -> String {
        guard index >= 0, index < 26 else { return "?" }
        return String(UnicodeScalar(65 + index)!)
    }

    private func letterBadge(_ letter: String, isSelected: Bool) -> some View {
        Text(letter)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: ChatToolInteractionCardStyle.badgeSize, height: ChatToolInteractionCardStyle.badgeSize)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill).opacity(0.7),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatToolInteractionCardStyle.cardCornerRadius, style: .continuous)
    }

    private var optionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatToolInteractionCardStyle.optionCornerRadius, style: .continuous)
    }
}

struct ChatToolMemberSelectionMessageCardView: View {
    let card: ChatToolMemberSelectionCard
    @ObservedObject var memberContextStore: MemberContextStore
    let onSubmit: (ChatToolMemberSelectionCard, Int) -> Void

    @State private var optimisticSelectedMemberID: Int?

    private var members: [Member] {
        memberContextStore.context.members
    }

    private var effectiveSelectedMemberID: Int? {
        card.selectedMemberID ?? optimisticSelectedMemberID
    }

    private var isResolved: Bool {
        card.status != .pending || optimisticSelectedMemberID != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isResolved {
                resolvedSummary
            } else if members.isEmpty {
                emptyState
            } else {
                interactiveContent
            }
        }
        .padding(ChatToolInteractionCardStyle.cardPadding)
        .background(ChatToolInteractionCardStyle.cardBackground, in: cardShape)
        .overlay {
            cardShape.strokeBorder(ChatToolInteractionCardStyle.borderColor, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
        .padding(.top, 8)
    }

    private var interactiveContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader

            Text(card.prompt.reason)
                .font(.system(size: ChatToolInteractionCardStyle.bodyFontSize))
                .foregroundStyle(.primary)
                .padding(.top, 12)

            VStack(spacing: 10) {
                ForEach(members) { member in
                    memberRow(member)
                }
            }
            .padding(.top, 12)

            Text("未选择成员将无法继续使用该工具。")
                .font(.system(size: ChatToolInteractionCardStyle.footerFontSize))
                .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
                .padding(.top, 12)
        }
    }

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: ChatToolInteractionCardStyle.badgeSize, height: ChatToolInteractionCardStyle.badgeSize)

            VStack(alignment: .leading, spacing: 2) {
                Text("请选择成员")
                    .font(.system(size: ChatToolInteractionCardStyle.headerFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                Text("该工具需要确认要查询哪位家庭成员。")
                    .font(.system(size: ChatToolInteractionCardStyle.subtitleFontSize))
                    .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
            }
        }
    }

    private func memberRow(_ member: Member) -> some View {
        let isSelected = effectiveSelectedMemberID == member.id
        let isDisabled = card.status != .pending || optimisticSelectedMemberID != nil

        return Button {
            guard isDisabled == false else { return }
            optimisticSelectedMemberID = member.id
            onSubmit(card, member.id)
        } label: {
            HStack(spacing: 12) {
                memberAvatar(member)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.system(size: ChatToolInteractionCardStyle.optionTitleFontSize, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(memberSubtitle(member))
                        .font(.system(size: ChatToolInteractionCardStyle.optionDescriptionFontSize))
                        .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
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
                isSelected ? Color.accentColor.opacity(0.1) : ChatToolInteractionCardStyle.cardBackground,
                in: optionShape
            )
            .overlay {
                optionShape.strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.5) : ChatToolInteractionCardStyle.borderColor,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var resolvedSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(resolvedTitle, systemImage: resolvedIcon)
                .font(.system(size: ChatToolInteractionCardStyle.headerFontSize, weight: .semibold))
                .foregroundStyle(resolvedColor)
            if let name = card.selectedMemberName ?? members.first(where: { $0.id == effectiveSelectedMemberID })?.name {
                Text("已选择：\(name)")
                    .font(.system(size: ChatToolInteractionCardStyle.bodyFontSize, weight: .medium))
                    .foregroundStyle(.primary)
            }
            Text(card.resultText ?? "工具会继续使用该成员完成本次查询。")
                .font(.system(size: ChatToolInteractionCardStyle.footerFontSize))
                .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
        }
    }

    private var resolvedTitle: String {
        switch card.status {
        case .submitted:
            return "已选择成员"
        case .cancelled:
            return "已取消选择"
        case .expired:
            return "本次等待已失效"
        case .pending:
            return optimisticSelectedMemberID == nil ? "等待选择成员" : "已选择成员，正在继续"
        }
    }

    private var resolvedIcon: String {
        card.status == .submitted || optimisticSelectedMemberID != nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var resolvedColor: Color {
        card.status == .submitted || optimisticSelectedMemberID != nil ? .green : .secondary
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader
            Text("暂无可选择的成员档案")
                .font(.system(size: ChatToolInteractionCardStyle.bodyFontSize, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.top, 12)
            Text("请先创建家庭成员后，再继续使用健康数据工具。")
                .font(.system(size: ChatToolInteractionCardStyle.footerFontSize))
                .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
        }
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
        if member.relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
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

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatToolInteractionCardStyle.cardCornerRadius, style: .continuous)
    }

    private var optionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatToolInteractionCardStyle.optionCornerRadius, style: .continuous)
    }
}
