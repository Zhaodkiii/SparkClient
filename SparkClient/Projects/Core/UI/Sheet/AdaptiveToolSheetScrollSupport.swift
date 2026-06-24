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

/// Scrollable sheet body whose **content height** drives `.presentationDetents` (capped to ~72% of screen height).
struct AdaptiveToolSheetScrollView<Content: View>: View {
    private let content: Content
    private let bottomContentPadding: CGFloat
    private let extraChromeHeight: CGFloat
    private let minimumHeight: CGFloat

    init(
        bottomContentPadding: CGFloat = 80,
        extraChromeHeight: CGFloat = 64,
        minimumHeight: CGFloat = 300,
        @ViewBuilder content: () -> Content
    ) {
        self.bottomContentPadding = bottomContentPadding
        self.extraChromeHeight = extraChromeHeight
        self.minimumHeight = minimumHeight
        self.content = content()
    }

    var body: some View {
        scrollView
            .modifier(
                AdaptiveToolSheetHeightModifier(
                    extraChromeHeight: extraChromeHeight,
                    minimumHeight: minimumHeight
                )
            )
    }

    private var scrollView: some View {
        ScrollView {
            content
                .padding(.bottom, bottomContentPadding)
                .readAdaptiveSheetHeight()
        }
    }
}

struct AdaptiveToolSheetHeightModifier: ViewModifier {
    /// Fixed chrome **outside** the measured scroll content (e.g. navigation bar, or header + footer rows).
    var extraChromeHeight: CGFloat = 64
    var minimumHeight: CGFloat = 300

    @State private var measuredHeight: CGFloat = AdaptiveSheetHeightPreferenceKey.defaultValue
    @State private var selectedDetent: PresentationDetent = .height(AdaptiveSheetHeightPreferenceKey.defaultValue)

    private var maxFittedHeight: CGFloat {
        UIScreen.main.bounds.height * 0.8
    }

    private var resolvedHeight: CGFloat {
        max(measuredHeight, minimumHeight)
    }

    private var fittedHeight: CGFloat {
        min(resolvedHeight, maxFittedHeight)
    }

    private var canScroll: Bool {
        resolvedHeight > maxFittedHeight && selectedDetent == .large
    }

    func body(content: Content) -> some View {
        content
            .scrollDisabled(canScroll == false)
            .onPreferenceChange(AdaptiveSheetHeightPreferenceKey.self) { height in
                guard height > 0 else { return }
                let nextHeight = height + extraChromeHeight
                measuredHeight = nextHeight
                let detentHeight = min(max(nextHeight, minimumHeight), maxFittedHeight)
                if selectedDetent != .large || detentHeight <= maxFittedHeight {
                    selectedDetent = .height(detentHeight)
                }
            }
            .presentationDetents(detents, selection: $selectedDetent)
            .presentationDragIndicator(.visible)
            .onAppear {
                measuredHeight = max(measuredHeight, minimumHeight)
                selectedDetent = .height(fittedHeight)
            }
    }

    private var detents: Set<PresentationDetent> {
        resolvedHeight > maxFittedHeight ? [.height(fittedHeight), .large] : [.height(fittedHeight)]
    }
}
