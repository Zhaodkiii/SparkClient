import SwiftUI

enum OnboardingVisualStyle {
    static let heroRatio: CGFloat = 0.68
    static let detailRatio: CGFloat = 0.32
    static let horizontalPadding: CGFloat = 24
    static let cardCornerRadius: CGFloat = 34
    static let buttonCornerRadius: CGFloat = 22

    static var accent: Color { Color("AccentColor") }
    static var accentSoft: Color { accent.opacity(0.12) }
    static var accentStroke: Color { accent.opacity(0.22) }
    static var pillBackground: Color { Color(.secondarySystemBackground).opacity(0.92) }
}
