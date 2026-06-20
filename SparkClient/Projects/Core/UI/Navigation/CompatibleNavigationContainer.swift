import SwiftUI

/// Navigation container backed by `NavigationStack`.
struct CompatibleNavigationContainer<Content: View>: View {
    private let content: () -> Content

    init(
        legacyStackStyle: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.content = content
    }

    var body: some View {
        NavigationStack {
            content()
        }
    }
}

/// Typed navigation container backed by `NavigationStack(path:)`.
struct CompatibleRouteNavigationContainer<Route: Hashable, Content: View, Destination: View>: View {
    @Binding private var path: [Route]
    private let content: () -> Content
    private let destination: (Route) -> Destination

    init(
        path: Binding<[Route]>,
        legacyStackStyle: Bool = false,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self._path = path
        self.content = content
        self.destination = destination
    }

    var body: some View {
        NavigationStack(path: $path) {
            content()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                        .hidesMainTabBarWhenPushed()
                }
        }
    }
}
