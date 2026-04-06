import Combine
import Foundation

@MainActor
final class AppRouteStore: ObservableObject {
    enum RootTab: Int, Hashable {
        case home
        case health
        case knowledge
        case chat
        case settings
    }

    @Published var selectedTab: RootTab = .home

    func resetForNewSession() {
        selectedTab = .home
    }
}
