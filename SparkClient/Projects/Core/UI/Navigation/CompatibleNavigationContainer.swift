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

/// Cross-version typed navigation container: iOS 16+ consumes a typed path;
/// iOS 15 bridges `path.last` through a hidden `NavigationLink`.
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
        } else {
            LegacyRouteNavigationBridge(
                path: $path,
                content: content,
                destination: destination
            )
        }
    }
}

/// iOS 15 typed-route bridge: observes `path.last` and drives a hidden push link.
private struct LegacyRouteNavigationBridge<Route: Hashable, Content: View, Destination: View>: View {
    @Binding private var path: [Route]
    private let content: () -> Content
    private let destination: (Route) -> Destination

    @State private var legacyPresentedRoute: Route?
    @State private var legacyIsActive = false

    init(
        path: Binding<[Route]>,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self._path = path
        self.content = content
        self.destination = destination
    }

    var body: some View {
        NavigationView {
            ZStack {
                content()

                NavigationLink(
                    isActive: Binding(
                        get: { legacyIsActive && legacyPresentedRoute != nil },
                        set: { isActive in
                            handleLegacyNavigationActiveChange(isActive)
                        }
                    )
                ) {
                    Group {
                        if let route = legacyPresentedRoute {
                            destination(route)
                                .hidesMainTabBarWhenPushed()
                        } else {
                            EmptyView()
                        }
                    }
                } label: {
                    EmptyView()
                }
                .hidden()
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            syncLegacyRoute(from: path)
        }
        .onChange(of: path) { newValue in
            syncLegacyRoute(from: newValue)
        }
    }

    private func handleLegacyNavigationActiveChange(_ isActive: Bool) {
        if isActive {
            legacyIsActive = true
            return
        }

        guard legacyIsActive else { return }

        let poppedRoute = legacyPresentedRoute
        legacyIsActive = false
        legacyPresentedRoute = nil

        guard path.isEmpty == false else { return }

        if let poppedRoute {
            SparkLogger.log(
                level: .info,
                module: .general,
                message: "legacy_route_pop route=\(String(describing: poppedRoute))"
            )
        }
        path = []
    }

    private func syncLegacyRoute(from path: [Route]) {
        SparkLogger.log(
            level: .debug,
            module: .general,
            message: "legacy_route_sync pathCount=\(path.count) last=\(path.last.map { String(describing: $0) } ?? "nil")"
        )

        if let next = path.last {
            if legacyPresentedRoute != next {
                SparkLogger.log(
                    level: .info,
                    module: .general,
                    message: "legacy_route_push route=\(String(describing: next))"
                )
            }
            legacyPresentedRoute = next
            legacyIsActive = true
            return
        }

        legacyIsActive = false
        legacyPresentedRoute = nil
    }
}
