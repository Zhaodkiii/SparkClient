import SwiftUI

/// 按条件包裹纵向 `ScrollView`：条数不足时直接展示内容，避免无效嵌套滚动。
struct ConditionalVerticalScroll<Content: View>: View {
    let isScrollable: Bool
    let maxHeight: CGFloat?
    let showsIndicators: Bool
    @ViewBuilder let content: () -> Content

    init(
        isScrollable: Bool,
        maxHeight: CGFloat? = nil,
        showsIndicators: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isScrollable = isScrollable
        self.maxHeight = maxHeight
        self.showsIndicators = showsIndicators
        self.content = content
    }

    var body: some View {
        if isScrollable {
            ScrollView(.vertical, showsIndicators: showsIndicators) {
                content()
            }
            .frame(maxHeight: maxHeight)
            .sparkScrollEnabled(true)
        } else {
            content()
        }
    }
}

extension View {
    /// 控制当前层级滚动。
    func sparkScrollEnabled(_ enabled: Bool) -> some View {
        self
            .scrollDisabled(!enabled)
            .environment(\.isScrollEnabled, enabled)
    }
}
