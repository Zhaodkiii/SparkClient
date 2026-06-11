import SwiftUI

/// Cross-version navigation container: iOS 16+ uses NavigationStack, older systems fall back to NavigationView.
struct CompatibleNavigationContainer<Content: View>: View {
    private let legacyStackStyle: Bool
    private let content: () -> Content

    init(
        legacyStackStyle: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.legacyStackStyle = legacyStackStyle
        self.content = content
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content()
            }
        } else if legacyStackStyle {
            NavigationView {
                content()
            }
            .navigationViewStyle(.stack)
        } else {
            NavigationView {
                content()
            }
        }
    }
}

/// Cross-version typed navigation container: iOS 16+ consumes a typed path,
/// while iOS 15 keeps the existing NavigationView behavior.
struct CompatibleRouteNavigationContainer<Route: Hashable, Content: View, Destination: View>: View {
    @Binding private var path: [Route]
    private let legacyStackStyle: Bool
    private let content: () -> Content
    private let destination: (Route) -> Destination

    init(
        path: Binding<[Route]>,
        legacyStackStyle: Bool = false,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self._path = path
        self.legacyStackStyle = legacyStackStyle
        self.content = content
        self.destination = destination
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(path: $path) {
                content()
                    .navigationDestination(for: Route.self) { route in
                        destination(route)
                            .hidesMainTabBarWhenPushed()
                    }
            }
        } else if legacyStackStyle {
            NavigationView {
                content()
            }
            .navigationViewStyle(.stack)
        } else {
            NavigationView {
                content()
            }
        }
    }
}
