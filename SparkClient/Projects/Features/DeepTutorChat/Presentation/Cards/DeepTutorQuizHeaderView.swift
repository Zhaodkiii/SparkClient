import SwiftUI

struct DeepTutorQuizHeaderView: View {
    let total: Int
    let currentIndex: Int
    let completedCount: Int
    let chipStates: [DeepTutorQuizChipState]
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelectIndex: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                navButton(systemName: "chevron.left", disabled: currentIndex <= 0, action: onPrevious)

                Text("\(completedCount)/\(total)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36)

                HStack(spacing: 6) {
                    ForEach(0..<total, id: \.self) { index in
                        Button {
                            onSelectIndex(index)
                        } label: {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .background(chipStates[index].background)
                                .foregroundStyle(chipStates[index].foreground)
                                .clipShape(Circle())
                                .overlay {
                                    Circle().stroke(chipStates[index].border, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)

                navButton(systemName: "chevron.right", disabled: currentIndex >= total - 1, action: onNext)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.tertiarySystemFill))
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * progressFraction)
                        .animation(.easeInOut(duration: 0.3), value: currentIndex)
                }
            }
            .frame(height: 2)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DeepTutorPalette.borderColor)
                .frame(height: 1)
        }
    }

    private var progressFraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(currentIndex + 1) / CGFloat(total)
    }

    private func navButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color(.tertiarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DeepTutorPalette.borderColor, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

enum DeepTutorQuizChipState {
    case current
    case unanswered
    case correct
    case incorrect
    case submittedOpenEnded

    var background: Color {
        switch self {
        case .current: return Color.accentColor
        case .unanswered: return Color(.tertiarySystemFill)
        case .correct: return Color.green.opacity(0.15)
        case .incorrect: return Color.red.opacity(0.15)
        case .submittedOpenEnded: return Color.accentColor.opacity(0.12)
        }
    }

    var foreground: Color {
        switch self {
        case .current: return .white
        case .unanswered: return .secondary
        case .correct: return .green
        case .incorrect: return .red
        case .submittedOpenEnded: return Color.accentColor
        }
    }

    var border: Color {
        switch self {
        case .current: return Color.accentColor
        case .unanswered: return DeepTutorPalette.mutedBorderColor
        case .correct: return Color.green.opacity(0.35)
        case .incorrect: return Color.red.opacity(0.35)
        case .submittedOpenEnded: return Color.accentColor.opacity(0.35)
        }
    }
}
