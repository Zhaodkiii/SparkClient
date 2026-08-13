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
                Text(L10n.text("chat.tool_interaction.question.title", fallback: "请作答以继续"))
                    .font(.system(size: ChatToolInteractionCardStyle.headerFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                Text(L10n.text("chat.tool_interaction.question.subtitle", fallback: "该工具需要你的补充选择。"))
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
                        L10n.text("chat.tool_interaction.question.other_placeholder", fallback: "输入自定义回复"),
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
            Text(L10n.text("chat.tool_interaction.question.footer", fallback: "提交后工具会继续执行。"))
                .font(.system(size: ChatToolInteractionCardStyle.footerFontSize))
                .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(L10n.text("chat.tool_interaction.common.submit", fallback: "提交")) {
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
            return L10n.text("chat.tool_interaction.question.submitted", fallback: "已提交回答")
        case .cancelled:
            return L10n.text("chat.tool_interaction.question.cancelled", fallback: "已取消回答")
        case .expired:
            return L10n.text("chat.tool_interaction.common.expired", fallback: "本次等待已失效")
        case .pending:
            return L10n.text("chat.tool_interaction.question.pending", fallback: "等待回答")
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
        return [card.resultText ?? L10n.text("chat.tool_interaction.question.finished_fallback", fallback: "工具等待已经结束。")]
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
        let listSeparator = L10n.text("chat.tool_interaction.common.list_separator", fallback: "，")
        return parts.isEmpty
            ? L10n.format("chat.tool_interaction.question.skipped_format", fallback: "已跳过：%@", question.question)
            : L10n.format(
                "chat.tool_interaction.question.answer_format",
                fallback: "%@：%@",
                question.question,
                parts.joined(separator: listSeparator)
            )
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

            Text(L10n.text("chat.tool_interaction.member_selection.footer", fallback: "未选择成员将无法继续使用该工具。"))
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
                Text(L10n.text("chat.tool_interaction.member_selection.title", fallback: "请选择成员"))
                    .font(.system(size: ChatToolInteractionCardStyle.headerFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                Text(L10n.text("chat.tool_interaction.member_selection.subtitle", fallback: "该工具需要确认要查询哪位家庭成员。"))
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
                Text(L10n.format("chat.tool_interaction.member_selection.selected_format", fallback: "已选择：%@", name))
                    .font(.system(size: ChatToolInteractionCardStyle.bodyFontSize, weight: .medium))
                    .foregroundStyle(.primary)
            }
            Text(card.resultText ?? L10n.text("chat.tool_interaction.member_selection.continue_with_member", fallback: "工具会继续使用该成员完成本次查询。"))
                .font(.system(size: ChatToolInteractionCardStyle.footerFontSize))
                .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
        }
    }

    private var resolvedTitle: String {
        switch card.status {
        case .submitted:
            return L10n.text("chat.tool_interaction.member_selection.submitted", fallback: "已选择成员")
        case .cancelled:
            return L10n.text("chat.tool_interaction.member_selection.cancelled", fallback: "已取消选择")
        case .expired:
            return L10n.text("chat.tool_interaction.common.expired", fallback: "本次等待已失效")
        case .pending:
            return optimisticSelectedMemberID == nil
                ? L10n.text("chat.tool_interaction.member_selection.pending", fallback: "等待选择成员")
                : L10n.text("chat.tool_interaction.member_selection.continuing", fallback: "已选择成员，正在继续")
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
            Text(L10n.text("chat.tool_interaction.member_selection.empty_title", fallback: "暂无可选择的成员档案"))
                .font(.system(size: ChatToolInteractionCardStyle.bodyFontSize, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.top, 12)
            Text(L10n.text("chat.tool_interaction.member_selection.empty_message", fallback: "请先创建家庭成员后，再继续使用健康数据工具。"))
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
                parts.append(L10n.format("chat.tool_interaction.member_selection.age_years_format", fallback: "%d岁", years))
            }
        }
        if member.gender != "unknown" {
            parts.append(member.gender)
        }
        return parts.joined(separator: L10n.text("chat.tool_interaction.common.separator", fallback: " · "))
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatToolInteractionCardStyle.cardCornerRadius, style: .continuous)
    }

    private var optionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatToolInteractionCardStyle.optionCornerRadius, style: .continuous)
    }
}

struct ChatHealthResourceCandidateMessageCardView: View {
    let card: ChatHealthResourceCandidateSelectionCard
    let onChoose: (ChatHealthResourceCandidateSelectionCard) -> Void
    let onSkip: (ChatHealthResourceCandidateSelectionCard) -> Void

    private var isResolved: Bool {
        card.status != .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader

            if isResolved {
                resolvedSummary
                    .padding(.top, 12)
            } else {
                candidatePreview
                    .padding(.top, 12)
                footerActions
                    .padding(.top, 12)
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

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: ChatToolInteractionCardStyle.badgeSize, height: ChatToolInteractionCardStyle.badgeSize)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(isResolved ? resolvedTitle : L10n.text("chat.tool_interaction.health_resource.title", fallback: "选择健康资料以继续"))
                    .font(.system(size: ChatToolInteractionCardStyle.headerFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                Text(isResolved ? resolvedSubtitle : L10n.text("chat.tool_interaction.health_resource.subtitle", fallback: "AI 找到多份可能相关的资料，你可以选择本次解读范围。"))
                    .font(.system(size: ChatToolInteractionCardStyle.subtitleFontSize))
                    .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var candidatePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(card.prompt.candidates.prefix(3)) { candidate in
                candidateRow(candidate)
            }
            if card.prompt.candidates.count > 3 {
                Text(
                    L10n.format(
                        "chat.tool_interaction.health_resource.remaining_format",
                        fallback: "还有 %d 份资料可选",
                        card.prompt.candidates.count - 3
                    )
                )
                    .font(.system(size: ChatToolInteractionCardStyle.footerFontSize))
                    .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
            }
        }
    }

    private func candidateRow(_ candidate: HealthResourceToolCandidateDTO) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(candidate.title)
                .font(.system(size: ChatToolInteractionCardStyle.optionTitleFontSize, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            HStack(spacing: 6) {
                if let occurredAt = candidate.occurredAt, occurredAt.isEmpty == false {
                    Text(occurredAt)
                }
                if let institution = candidate.institution, institution.isEmpty == false {
                    Text(institution)
                }
            }
            .font(.system(size: ChatToolInteractionCardStyle.optionDescriptionFontSize))
            .foregroundStyle(.secondary)
            Text(candidate.matchReason)
                .font(.system(size: ChatToolInteractionCardStyle.optionDescriptionFontSize))
                .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.systemBackground).opacity(0.6), in: optionShape)
        .overlay {
            optionShape.strokeBorder(ChatToolInteractionCardStyle.borderColor, lineWidth: 1)
        }
    }

    private var footerActions: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(L10n.text("chat.tool_interaction.health_resource.footer", fallback: "选择或跳过后，AI 会继续回答。"))
                .font(.system(size: ChatToolInteractionCardStyle.footerFontSize))
                .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(L10n.text("chat.tool_interaction.common.skip", fallback: "跳过")) {
                onSkip(card)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .buttonStyle(.plain)

            Button(L10n.text("chat.tool_interaction.health_resource.choose_action", fallback: "选择资料")) {
                onChoose(card)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .buttonStyle(.plain)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ChatToolInteractionCardStyle.borderColor.opacity(0.6))
                .frame(height: 1)
        }
        .padding(.top, 12)
    }

    private var resolvedSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(resolvedTitle, systemImage: card.status == .submitted ? "checkmark.circle.fill" : "forward.circle.fill")
                .font(.system(size: ChatToolInteractionCardStyle.headerFontSize, weight: .semibold))
                .foregroundStyle(card.status == .submitted ? .green : .secondary)

            if card.selectedCandidates.isEmpty {
                Text(card.resultText ?? L10n.text("chat.tool_interaction.health_resource.skipped_fallback", fallback: "已跳过资料选择。"))
                    .font(.system(size: ChatToolInteractionCardStyle.bodyFontSize))
                    .foregroundStyle(.primary)
            } else {
                ForEach(card.selectedCandidates) { candidate in
                    Text(candidate.title)
                        .font(.system(size: ChatToolInteractionCardStyle.bodyFontSize))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var resolvedTitle: String {
        switch card.status {
        case .submitted:
            return L10n.text("chat.tool_interaction.health_resource.submitted", fallback: "已选择健康资料")
        case .cancelled:
            return L10n.text("chat.tool_interaction.health_resource.cancelled", fallback: "已跳过资料选择")
        case .expired:
            return L10n.text("chat.tool_interaction.common.expired", fallback: "本次等待已失效")
        case .pending:
            return L10n.text("chat.tool_interaction.health_resource.pending", fallback: "等待选择健康资料")
        }
    }

    private var resolvedSubtitle: String {
        if card.selectedCandidates.isEmpty {
            return L10n.text("chat.tool_interaction.health_resource.continue_without_scope", fallback: "AI 将在未限定资料范围的情况下继续。")
        }
        return L10n.text("chat.tool_interaction.health_resource.continue_with_selection", fallback: "AI 将基于已选资料继续。")
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatToolInteractionCardStyle.cardCornerRadius, style: .continuous)
    }

    private var optionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatToolInteractionCardStyle.optionCornerRadius, style: .continuous)
    }
}

struct ChatToolConsentMessageCardView: View {
    let card: ChatToolConsentCard
    let onAllow: (ChatToolConsentCard) -> Void
    let onDeny: (ChatToolConsentCard) -> Void
    let onShowDetails: (ChatToolConsentCard) -> Void
    let onOpenSettings: (ChatToolConsentCard) -> Void

    private var isResolved: Bool {
        card.status != .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 8) {
                ForEach(card.prompt.dataLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: ChatToolInteractionCardStyle.optionDescriptionFontSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                providerLine
            }
            .padding(.top, 12)

            if isResolved {
                resolvedSummary
                    .padding(.top, 12)
            } else {
                actions
                    .padding(.top, 12)
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

    private var header: some View {
        Button {
            onOpenSettings(card)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: ChatToolInteractionCardStyle.badgeSize, height: ChatToolInteractionCardStyle.badgeSize)
                    .background(Color.accentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(isResolved ? resolvedTitle : L10n.text("chat.tool_interaction.consent.title", fallback: "将工具结果发送至 AI"))
                        .font(.system(size: ChatToolInteractionCardStyle.headerFontSize, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(L10n.text("chat.tool_interaction.consent.subtitle", fallback: "工具已在本地完成，继续前需要确认是否发送结果给模型。"))
                        .font(.system(size: ChatToolInteractionCardStyle.subtitleFontSize))
                        .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
                    .padding(.top, 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var providerLine: some View {
        HStack(spacing: 6) {
            Text(card.prompt.providerCompany)
            Text(card.prompt.modelLine)
        }
        .font(.system(size: ChatToolInteractionCardStyle.footerFontSize))
        .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
    }

    private var actions: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(L10n.text("chat.tool_interaction.common.deny", fallback: "拒绝")) {
                onDeny(card)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .buttonStyle(.plain)

            Button(L10n.text("chat.tool_interaction.common.view_details", fallback: "查看详情")) {
                onShowDetails(card)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .buttonStyle(.plain)

            Button(L10n.text("chat.tool_interaction.consent.allow_always", fallback: "始终允许")) {
                onAllow(card)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ChatToolInteractionCardStyle.borderColor.opacity(0.6))
                .frame(height: 1)
        }
        .padding(.top, 12)
    }

    private var resolvedSummary: some View {
        Label(card.resultText ?? resolvedTitle, systemImage: card.decision?.allowed == true ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: ChatToolInteractionCardStyle.headerFontSize, weight: .semibold))
            .foregroundStyle(card.decision?.allowed == true ? .green : .secondary)
    }

    private var resolvedTitle: String {
        if card.decision?.allowed == true {
            return card.decision?.rememberTool == true
                ? L10n.text("chat.tool_interaction.consent.remembered", fallback: "已始终允许")
                : L10n.text("chat.tool_interaction.consent.allowed", fallback: "已允许发送")
        }
        return L10n.text("chat.tool_interaction.consent.denied", fallback: "已拒绝发送")
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatToolInteractionCardStyle.cardCornerRadius, style: .continuous)
    }
}

struct ChatLocationPermissionMessageCardView: View {
    let card: ChatLocationPermissionCard
    let onAction: (ChatLocationPermissionCard) -> Void

    private var isResolved: Bool {
        card.status != .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Text(bodyText)
                .font(.system(size: ChatToolInteractionCardStyle.bodyFontSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            if isResolved {
                resolvedSummary
                    .padding(.top, 12)
            } else {
                actionButton
                    .padding(.top, 12)
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

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: ChatToolInteractionCardStyle.badgeSize, height: ChatToolInteractionCardStyle.badgeSize)
                .background(accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: ChatToolInteractionCardStyle.headerFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: ChatToolInteractionCardStyle.subtitleFontSize))
                    .foregroundStyle(ChatToolInteractionCardStyle.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button(actionTitle) {
                onAction(card)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .buttonStyle(.plain)
        }
    }

    private var resolvedSummary: some View {
        Label(card.resultText ?? resolvedText, systemImage: resolvedIcon)
            .font(.system(size: ChatToolInteractionCardStyle.headerFontSize, weight: .semibold))
            .foregroundStyle(resolvedColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var title: String {
        switch card.mode {
        case .requestPermission:
            return isResolved
                ? resolvedTitle
                : L10n.text("chat.tool_interaction.location_permission.request_title", fallback: "需要位置权限")
        case .openSettings:
            return L10n.text("chat.tool_interaction.location_permission.open_settings_title", fallback: "无法获取当前位置")
        }
    }

    private var subtitle: String {
        switch card.mode {
        case .requestPermission:
            return L10n.text("chat.tool_interaction.location_permission.request_subtitle", fallback: "授权后将重新获取当前位置并继续回复。")
        case .openSettings:
            return L10n.text("chat.tool_interaction.location_permission.open_settings_subtitle", fallback: "你可以前往系统设置开启位置权限。")
        }
    }

    private var bodyText: String {
        switch card.mode {
        case .requestPermission:
            return L10n.text("chat.tool_interaction.location_permission.request_body", fallback: "AI 需要你的当前位置来完成本次查询。点击授权后，系统会弹出位置权限确认。")
        case .openSettings:
            return L10n.text("chat.tool_interaction.location_permission.open_settings_body", fallback: "当前应用没有位置权限，因此本次无法读取当前位置。AI 会基于无权限状态继续回答。")
        }
    }

    private var actionTitle: String {
        switch card.mode {
        case .requestPermission:
            return L10n.text("chat.tool_interaction.location_permission.allow_action", fallback: "允许位置")
        case .openSettings:
            return L10n.text("chat.tool_interaction.common.open_settings", fallback: "打开设置")
        }
    }

    private var accentColor: Color {
        card.mode == .openSettings ? .orange : .accentColor
    }

    private var resolvedTitle: String {
        card.result == .authorized
            ? L10n.text("chat.tool_interaction.location_permission.authorized_title", fallback: "已允许位置权限")
            : L10n.text("chat.tool_interaction.location_permission.denied_title", fallback: "未允许位置权限")
    }

    private var resolvedText: String {
        card.result == .authorized
            ? L10n.text("chat.tool_interaction.location_permission.authorized_result", fallback: "用户已允许位置权限。")
            : L10n.text("chat.tool_interaction.location_permission.denied_result", fallback: "用户未允许位置权限。")
    }

    private var resolvedIcon: String {
        card.result == .authorized ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var resolvedColor: Color {
        card.result == .authorized ? .green : .secondary
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatToolInteractionCardStyle.cardCornerRadius, style: .continuous)
    }
}
