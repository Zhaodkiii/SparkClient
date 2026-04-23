import SwiftUI

extension View {
    /// Hide the root `TabView` bar while this view is displayed as a pushed detail page.
    @ViewBuilder
    func hidesMainTabBarWhenPushed() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .tabBar)
        } else {
            self
        }
    }
}
