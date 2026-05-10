import SwiftUI

// MARK: - Measured height → presentation detent (shared by Chat tool sheets, medicine box strength sheet, etc.)

struct AdaptiveSheetHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 300

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func readAdaptiveSheetHeight() -> some View {
        overlay {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: AdaptiveSheetHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        }
    }
}

/// Scrollable sheet body whose **content height** drives `.presentationDetents` on iOS 16+ (capped to ~72% of screen height).
struct AdaptiveToolSheetScrollView<Content: View>: View {
    private let content: Content
    private let bottomContentPadding: CGFloat
    private let extraChromeHeight: CGFloat

    init(
        bottomContentPadding: CGFloat = 80,
        extraChromeHeight: CGFloat = 64,
        @ViewBuilder content: () -> Content
    ) {
        self.bottomContentPadding = bottomContentPadding
        self.extraChromeHeight = extraChromeHeight
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            scrollView
                .modifier(AdaptiveToolSheetHeightModifier(extraChromeHeight: extraChromeHeight))
        } else {
            scrollView
        }
    }

    private var scrollView: some View {
        ScrollView {
            content
                .padding(.bottom, bottomContentPadding)
                .readAdaptiveSheetHeight()
        }
//        .background(Color(uiColor: .systemGroupedBackground))
    }
}

@available(iOS 16.0, *)
struct AdaptiveToolSheetHeightModifier: ViewModifier {
    /// Fixed chrome **outside** the measured scroll content (e.g. navigation bar, or header + footer rows).
    var extraChromeHeight: CGFloat = 64

    @State private var measuredHeight: CGFloat = AdaptiveSheetHeightPreferenceKey.defaultValue
    @State private var selectedDetent: PresentationDetent = .height(AdaptiveSheetHeightPreferenceKey.defaultValue)

    private var maxFittedHeight: CGFloat {
        UIScreen.main.bounds.height * 0.72
    }

    private var fittedHeight: CGFloat {
        min(measuredHeight, maxFittedHeight)
    }

    private var canScroll: Bool {
        measuredHeight > maxFittedHeight && selectedDetent == .large
    }

    func body(content: Content) -> some View {
        content
            .scrollDisabled(canScroll == false)
            .onPreferenceChange(AdaptiveSheetHeightPreferenceKey.self) { height in
                guard height > 0 else { return }
                let nextHeight = height + extraChromeHeight
                measuredHeight = nextHeight
                if selectedDetent != .large || nextHeight <= maxFittedHeight {
                    selectedDetent = .height(min(nextHeight, maxFittedHeight))
                }
            }
            .presentationDetents(detents, selection: $selectedDetent)
            .presentationDragIndicator(.visible)
    }

    private var detents: Set<PresentationDetent> {
        measuredHeight > maxFittedHeight ? [.height(fittedHeight), .large] : [.height(measuredHeight)]
    }
}
