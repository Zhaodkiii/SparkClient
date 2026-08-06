import SwiftUI

struct DeepTutorQuizAnswerInputView: View {
    let question: DeepTutorQuizQuestion
    let selectedKey: String?
    let typedText: String
    let submitted: Bool
    let onSelectKey: (String) -> Void
    let onType: (String) -> Void
    var onInlineInputFocusChanged: ((Bool) -> Void)? = nil

    @FocusState private var isTextInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch question.questionType {
            case .choice:
                choiceInput
            case .concept:
                conceptInput
            case .fillInBlank:
                fillBlankInput
            case .shortAnswer, .written, .coding:
                freeTextInput(rows: question.questionType == .written ? 5 : question.questionType == .coding ? 6 : 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onChange(of: isTextInputFocused) { _, focused in
            onInlineInputFocusChanged?(focused)
        }
        .onChange(of: question.id) { _, _ in
            if isTextInputFocused {
                isTextInputFocused = false
                onInlineInputFocusChanged?(false)
            }
        }
        .onChange(of: submitted) { _, isSubmitted in
            if isSubmitted, isTextInputFocused {
                isTextInputFocused = false
                onInlineInputFocusChanged?(false)
            }
        }
        .onDisappear {
            if isTextInputFocused {
                onInlineInputFocusChanged?(false)
            }
        }
    }

    private var choiceInput: some View {
        VStack(spacing: 6) {
            ForEach(question.options) { option in
                let isSelected = selectedKey?.uppercased() == option.key.uppercased()
                let isCorrect = submitted && DeepTutorQuizGrader.resolveChoiceAnswerKey(
                    correctAnswer: question.correctAnswer,
                    options: question.options
                ).uppercased() == option.key.uppercased()
                let isWrongSelection = submitted && isSelected && isCorrect == false

                Button {
                    guard submitted == false else { return }
                    onSelectKey(option.key)
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .strokeBorder(rowBorder(isSelected: isSelected, isCorrect: isCorrect, isWrong: isWrongSelection), lineWidth: 1)
                                .background(
                                    Circle().fill(rowBadgeBackground(isSelected: isSelected, isCorrect: isCorrect, isWrong: isWrongSelection))
                                )
                                .frame(width: 20, height: 20)
                            if submitted && isCorrect {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text(option.key)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(rowBadgeForeground(isSelected: isSelected, isCorrect: isCorrect, isWrong: isWrongSelection))
                            }
                        }
                        DeepTutorMarkdownRenderer(markdown: option.text)
                            .font(.system(size: DeepTutorPalette.bodyFontSize))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(rowBackground(isSelected: isSelected, isCorrect: isCorrect, isWrong: isWrongSelection), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(rowBorder(isSelected: isSelected, isCorrect: isCorrect, isWrong: isWrongSelection), lineWidth: 1)
                    }
                    .overlay {
                        if isSelected && submitted == false {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.2), lineWidth: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(submitted && isSelected == false && isCorrect == false)
                .opacity(submitted && isSelected == false && isCorrect == false ? 0.55 : 1)
            }
        }
    }

    private var conceptInput: some View {
        HStack(spacing: 8) {
            conceptButton(title: "对", value: "true")
            conceptButton(title: "错", value: "false")
        }
    }

    private func conceptButton(title: String, value: String) -> some View {
        let isSelected = DeepTutorQuizGrader.resolveConceptAnswer(selectedKey) == value
        let correct = DeepTutorQuizGrader.resolveConceptAnswer(question.correctAnswer)
        let isCorrect = submitted && correct == value
        let isWrong = submitted && isSelected && isCorrect == false

        return Button {
            guard submitted == false else { return }
            onSelectKey(value)
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(rowBackground(isSelected: isSelected, isCorrect: isCorrect, isWrong: isWrong), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(rowBorder(isSelected: isSelected, isCorrect: isCorrect, isWrong: isWrong), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(submitted)
    }

    private var fillBlankInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("填空题")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(.secondary)
            TextField("在此输入答案…", text: Binding(
                get: { typedText },
                set: { onType($0) }
            ))
            .focused($isTextInputFocused)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(submitted ? Color(.tertiarySystemFill) : Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DeepTutorPalette.borderColor, lineWidth: 1)
            }
            .disabled(submitted)
        }
    }

    private func freeTextInput(rows: Int) -> some View {
        TextField("在此输入答案…", text: Binding(get: { typedText }, set: onType), axis: .vertical)
            .focused($isTextInputFocused)
            .lineLimit(rows...rows + 2)
            .font(.system(size: 13))
            .padding(12)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DeepTutorPalette.borderColor, lineWidth: 1)
            }
            .disabled(submitted)
    }

    private func rowBackground(isSelected: Bool, isCorrect: Bool, isWrong: Bool) -> Color {
        if isCorrect { return Color.green.opacity(0.12) }
        if isWrong { return Color.red.opacity(0.12) }
        if isSelected { return Color.accentColor.opacity(0.06) }
        return Color(.systemBackground)
    }

    private func rowBorder(isSelected: Bool, isCorrect: Bool, isWrong: Bool) -> Color {
        if isCorrect { return .green }
        if isWrong { return .red }
        if isSelected { return Color.accentColor }
        return DeepTutorPalette.borderColor
    }

    private func rowBadgeBackground(isSelected: Bool, isCorrect: Bool, isWrong: Bool) -> Color {
        if isCorrect { return .green }
        if isWrong { return .red }
        if isSelected { return Color.accentColor }
        return Color(.systemBackground)
    }

    private func rowBadgeForeground(isSelected: Bool, isCorrect: Bool, isWrong: Bool) -> Color {
        if isCorrect || isWrong || isSelected { return .white }
        return .primary
    }
}
