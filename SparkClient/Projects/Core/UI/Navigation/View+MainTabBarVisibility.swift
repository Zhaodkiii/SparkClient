import SwiftUI

extension View {
    /// Hide the root `TabView` bar while this view is displayed as a pushed detail page.
    func hidesMainTabBarWhenPushed() -> some View {
        modifier(MainTabBarVisibilityModifier())
    }
}

private struct MainTabBarVisibilityModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
//            content.toolbar(.hidden, for: .tabBar)
            content.background(LegacyTabBarHiddenHostingBridge())
        } else {
            content.background(LegacyTabBarHiddenHostingBridge())
        }
    }
}
