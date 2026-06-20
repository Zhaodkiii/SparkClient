import SwiftUI

private struct ShareSheetHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 420

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func readShareSheetHeight() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ShareSheetHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        }
    }
}

extension View {
    /// 分享页 bottom sheet：按内容高度自适应。
    func shareSheetPresentation() -> some View {
        modifier(ShareSheetPresentationModifier())
    }
}

private struct ShareSheetPresentationModifier: ViewModifier {
    @State private var sheetHeight: CGFloat = ShareSheetHeightPreferenceKey.defaultValue

    func body(content: Content) -> some View {
        content
            .readShareSheetHeight()
            .onPreferenceChange(ShareSheetHeightPreferenceKey.self) { height in
                guard height > 0 else { return }
                // 含底部取消按钮区域（safeAreaInset 不计入 preference）
                sheetHeight = min(height + 76, UIScreen.main.bounds.height * 0.88)
            }
            .presentationDetents([.height(sheetHeight)])
            .presentationDragIndicator(.visible)
    }
}
