import SwiftUI

struct DeepTutorAskUserCardView: View {
    let payload: DeepTutorAskUserBlockPayload
    let onSubmit: ([DeepTutorAskUserAnswer]) -> Void

    @State private var selectedOptionIDs: [String: Set<String>] = [:]
    @State private var freeTextAnswers: [String: String] = [:]
    @State private var expandedFreeTextQuestionIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let intro = payload.payload.intro, intro.isEmpty == false {
                Text(intro)
                    .font(.system(size: DeepTutorPalette.bodyFontSize))
                    .foregroundStyle(DeepTutorPalette.traceMutedText)
                    .padding(.bottom, 12)
            }

            if payload.isResolved {
                resolvedSummary
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
    }

    private var interactiveContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader

            ForEach(payload.payload.questions) { question in
                questionBlock(question)
            }

            footer
        }
    }

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("?")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.7))
                .frame(width: DeepTutorPalette.askUserBadgeSize, height: DeepTutorPalette.askUserBadgeSize)
                .background(Color.primary.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("请作答以继续。")
                    .font(.system(size: DeepTutorPalette.askUserHeaderFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                Text("选择一个选项或输入自定义回复以继续。")
                    .font(.system(size: DeepTutorPalette.askUserSubtitleFontSize))
                    .foregroundStyle(DeepTutorPalette.traceMutedText)
            }
        }
    }

    @ViewBuilder
    private func questionBlock(_ question: DeepTutorAskUserQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(question.prompt)
                .font(.system(size: DeepTutorPalette.bodyFontSize, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.top, 12)

            if question.options.isEmpty, question.allowFreeText {
                TextField(
                    question.placeholder ?? "输入你的回复",
                    text: binding(for: question.id)
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: DeepTutorPalette.askUserOptionTitleFontSize))
                .padding(.top, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                        optionRow(
                            questionID: question.id,
                            option: option,
                            letter: letter(for: index),
                            multiSelect: question.multiSelect,
                            isSelected: selectedOptionIDs[question.id, default: []].contains(option.id)
                        )
                    }

                    if question.allowFreeText {
                        otherRow(question: question, optionCount: question.options.count)
                        if expandedFreeTextQuestionIDs.contains(question.id) {
                            TextField(
                                question.placeholder ?? "输入自定义回复",
                                text: binding(for: question.id)
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: DeepTutorPalette.askUserOptionTitleFontSize))
                            .padding(.top, 4)
                            .onChange(of: freeTextAnswers[question.id, default: ""]) { _, newValue in
                                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                                    if question.multiSelect == false {
                                        selectedOptionIDs.removeValue(forKey: question.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func optionRow(
        questionID: String,
        option: DeepTutorAskUserOption,
        letter: String,
        multiSelect: Bool,
        isSelected: Bool
    ) -> some View {
        Button {
            if multiSelect {
                var selected = selectedOptionIDs[questionID, default: []]
                if selected.contains(option.id) {
                    selected.remove(option.id)
                } else {
                    selected.insert(option.id)
                }
                selectedOptionIDs[questionID] = selected
            } else {
                selectedOptionIDs[questionID] = [option.id]
                expandedFreeTextQuestionIDs.remove(questionID)
                freeTextAnswers[questionID] = ""
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                letterBadge(letter, isSelected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: DeepTutorPalette.askUserOptionTitleFontSize, weight: .regular))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let description = option.description, description.isEmpty == false {
                        Text(description)
                            .font(.system(size: DeepTutorPalette.askUserOptionDescriptionFontSize))
                            .foregroundStyle(DeepTutorPalette.traceMutedText)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DeepTutorPalette.cardBackground, in: optionRowShape)
            .overlay {
                optionRowShape.strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.5) : DeepTutorPalette.borderColor,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func otherRow(question: DeepTutorAskUserQuestion, optionCount: Int) -> some View {
        let letter = letter(for: optionCount)
        let isExpanded = expandedFreeTextQuestionIDs.contains(question.id)
        let hasFreeText = freeTextAnswers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        return Button {
            expandedFreeTextQuestionIDs.insert(question.id)
            if question.multiSelect == false {
                selectedOptionIDs.removeValue(forKey: question.id)
            }
        } label: {
            HStack(spacing: 12) {
                letterBadge(letter, isSelected: isExpanded || hasFreeText)
                Text("其他 — 自定义回复…")
                    .font(.system(size: DeepTutorPalette.askUserOptionTitleFontSize))
                    .foregroundStyle(DeepTutorPalette.traceMutedText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay {
                RoundedRectangle(cornerRadius: DeepTutorPalette.askUserOptionCornerRadius, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                    .foregroundStyle(
                        isExpanded || hasFreeText
                            ? Color.accentColor.opacity(0.5)
                            : DeepTutorPalette.borderColor
                    )
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func letterBadge(_ letter: String, isSelected: Bool) -> some View {
        Text(letter)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isSelected ? DeepTutorPalette.askUserBadgeSelectedText : DeepTutorPalette.askUserBadgeText)
            .frame(width: DeepTutorPalette.askUserBadgeSize, height: DeepTutorPalette.askUserBadgeSize)
            .background(
                isSelected
                    ? DeepTutorPalette.askUserBadgeSelectedBackground
                    : DeepTutorPalette.askUserBadgeBackground,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("未回答的问题将作为「已跳过」提交。")
                .font(.system(size: DeepTutorPalette.askUserFooterFontSize))
                .foregroundStyle(DeepTutorPalette.traceMutedText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Submit") {
                submitAnswers()
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
                .fill(DeepTutorPalette.borderColor.opacity(0.6))
                .frame(height: 1)
        }
        .padding(.top, 12)
    }

    private var resolvedSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("已提交回答", systemImage: "checkmark.circle.fill")
                .font(.system(size: DeepTutorPalette.askUserHeaderFontSize, weight: .semibold))
                .foregroundStyle(.green)
            ForEach(payload.answers, id: \.questionID) { answer in
                Text(answer.text)
                    .font(.system(size: DeepTutorPalette.bodyFontSize))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DeepTutorPalette.askUserCardCornerRadius, style: .continuous)
    }

    private var optionRowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DeepTutorPalette.askUserOptionCornerRadius, style: .continuous)
    }

    private func letter(for index: Int) -> String {
        guard index >= 0, index < 26 else { return "?" }
        return String(UnicodeScalar(65 + index)!)
    }

    private func binding(for questionID: String) -> Binding<String> {
        Binding(
            get: { freeTextAnswers[questionID, default: ""] },
            set: { freeTextAnswers[questionID] = $0 }
        )
    }

    private func submitAnswers() {
        var answers: [DeepTutorAskUserAnswer] = []
        for question in payload.payload.questions {
            var parts = question.options
                .filter { selectedOptionIDs[question.id, default: []].contains($0.id) }
                .map(\.label)
            if let text = freeTextAnswers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
               text.isEmpty == false {
                parts.append(text)
            }
            answers.append(
                DeepTutorAskUserAnswer(
                    questionID: question.id,
                    text: parts.joined(separator: ", ")
                )
            )
        }
        onSubmit(answers)
    }
}
