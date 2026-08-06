import SwiftUI

/// DeepTutor Web → iOS 视觉换算常量。
enum DeepTutorPalette {
    static let composerCornerRadius: CGFloat = 26
    static let bubbleCornerRadius: CGFloat = 18
    static let cardCornerRadius: CGFloat = 16
    static let askUserCardCornerRadius: CGFloat = 18
    static let askUserOptionCornerRadius: CGFloat = 12
    static let askUserBadgeSize: CGFloat = 24

    static let bodyFontSize: CGFloat = 14
    static let captionFontSize: CGFloat = 11
    static let askUserHeaderFontSize: CGFloat = 13
    static let askUserSubtitleFontSize: CGFloat = 11
    static let askUserOptionTitleFontSize: CGFloat = 13.5
    static let askUserOptionDescriptionFontSize: CGFloat = 11.5
    static let askUserFooterFontSize: CGFloat = 11.5
    static let traceBodyFontSize: CGFloat = 11
    static let traceDetailFontSize: CGFloat = 11.5
    static let badgeFontSize: CGFloat = 10

    static let bodyLineSpacing: CGFloat = 4
    static let bubbleHorizontalPadding: CGFloat = 16
    static let bubbleVerticalPadding: CGFloat = 10

    static let composerEmptyMinHeight: CGFloat = 64
    static let composerFilledMinHeight: CGFloat = 28
    static let composerMaxHeight: CGFloat = 200

    static var cardBackground: Color { Color(.systemBackground) }
    static var secondarySurface: Color { Color(.secondarySystemBackground) }
    static var mutedSurface: Color { Color(.tertiarySystemFill).opacity(0.45) }
    static var borderColor: Color { Color(.separator).opacity(0.55) }
    static var mutedBorderColor: Color { Color(.separator).opacity(0.3) }
    static var traceBorderColor: Color { Color(.separator).opacity(0.45) }
    static var traceHeaderText: Color { Color.secondary.opacity(0.7) }
    static var traceMutedText: Color { Color.secondary }
    static var askUserBadgeBackground: Color { Color(.tertiarySystemFill).opacity(0.7) }
    static var askUserBadgeText: Color { Color.secondary }
    static var askUserBadgeSelectedBackground: Color { Color.accentColor.opacity(0.15) }
    static var askUserBadgeSelectedText: Color { Color.accentColor }
    static var askUserRowHoverBorder: Color { Color.primary.opacity(0.3) }

    static func bubbleMaxWidth(for containerWidth: CGFloat) -> CGFloat {
        min(containerWidth * 0.88, 620)
    }
}

extension View {
    func deepTutorComposerCardShadow() -> some View {
        shadow(color: .black.opacity(0.025), radius: 1, x: 0, y: 1)
            .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
    }

    func deepTutorBubbleShadow() -> some View {
        shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    func deepTutorAskUserCardShadow() -> some View {
        shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.04), radius: 14, x: 0, y: 4)
    }
}
