import SwiftUI

struct DeepTutorQuizQuestionBodyView: View {
    let question: DeepTutorQuizQuestion
    let questionIndex: Int
    let submitted: Bool
    let bookmarked: Bool
    let onToggleBookmark: (() -> Void)?
    let onFollowUp: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                metaChip("Q\(questionIndex + 1)")
                if let difficulty = question.difficulty, difficulty.isEmpty == false {
                    metaChip(difficulty.uppercased(), tint: difficultyTint(difficulty))
                }
                metaChip(question.questionType.displayLabel)
                Spacer()
                if submitted {
                    submittedActions
                }
            }

            DeepTutorMarkdownRenderer(markdown: question.question)
                .font(.system(size: DeepTutorPalette.bodyFontSize))
                .lineSpacing(DeepTutorPalette.bodyLineSpacing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var submittedActions: some View {
        HStack(spacing: 6) {
            if let onToggleBookmark {
                Button(action: onToggleBookmark) {
                    Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(bookmarked ? Color.accentColor : .secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            if let onFollowUp {
                Button(action: onFollowUp) {
                    Label("追问", systemImage: "message.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metaChip(_ text: String, tint: Color = Color(.tertiarySystemFill)) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(text == text.uppercased() && tint != Color(.tertiarySystemFill) ? 1 : 0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(text == text.uppercased() && tint != Color(.tertiarySystemFill) ? tintForeground(tint) : .secondary)
    }

    private func difficultyTint(_ difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "easy": return .green
        case "hard": return .red
        default: return .orange
        }
    }

    private func tintForeground(_ tint: Color) -> Color {
        tint == .green ? .green : tint == .red ? .red : .orange
    }
}
