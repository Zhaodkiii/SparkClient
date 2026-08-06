import SwiftUI

struct DeepTutorQuizReviewPanelView: View {
    let question: DeepTutorQuizQuestion
    let collapsed: Bool
    let aiJudgment: String?
    let reviewViewMode: DeepTutorQuizReviewViewMode
    let onToggle: () -> Void
    let onSelectViewMode: (DeepTutorQuizReviewViewMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Text(headerTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if collapsed == false {
                if aiJudgment?.isEmpty == false {
                    HStack(spacing: 8) {
                        reviewTab(title: "参考答案", mode: .reference)
                        reviewTab(title: "AI 判定", mode: .judgment)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if reviewViewMode == .judgment, let aiJudgment, aiJudgment.isEmpty == false {
                        DeepTutorMarkdownRenderer(markdown: aiJudgment)
                            .font(.system(size: DeepTutorPalette.bodyFontSize))
                    } else {
                        if shouldShowReferenceAnswer {
                            Text("参考答案")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            DeepTutorMarkdownRenderer(markdown: referenceAnswerMarkdown)
                                .font(.system(size: DeepTutorPalette.bodyFontSize))
                        }

                        if question.explanation.isEmpty == false {
                            Text("解析")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            DeepTutorMarkdownRenderer(markdown: question.explanation)
                                .font(.system(size: DeepTutorPalette.bodyFontSize))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DeepTutorPalette.borderColor, lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var headerTitle: String {
        if aiJudgment?.isEmpty == false, reviewViewMode == .judgment {
            return "AI 判定"
        }
        return "参考答案 / 解析"
    }

    private func reviewTab(title: String, mode: DeepTutorQuizReviewViewMode) -> some View {
        Button {
            onSelectViewMode(mode)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    reviewViewMode == mode ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill),
                    in: Capsule()
                )
                .foregroundStyle(reviewViewMode == mode ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var shouldShowReferenceAnswer: Bool {
        switch question.questionType {
        case .choice, .concept:
            return false
        case .fillInBlank, .shortAnswer, .written, .coding:
            return question.correctAnswer.isEmpty == false
        }
    }

    private var referenceAnswerMarkdown: String {
        switch question.questionType {
        case .concept:
            return DeepTutorQuizGrader.resolveConceptAnswer(question.correctAnswer) == "true" ? "对" : "错"
        case .choice:
            let key = DeepTutorQuizGrader.resolveChoiceAnswerKey(
                correctAnswer: question.correctAnswer,
                options: question.options
            )
            if let option = question.options.first(where: { $0.key.uppercased() == key.uppercased() }) {
                return "**\(option.key).** \(option.text)"
            }
            return question.correctAnswer
        default:
            if question.questionType == .coding {
                return "```\n\(question.correctAnswer)\n```"
            }
            return question.correctAnswer
        }
    }
}
