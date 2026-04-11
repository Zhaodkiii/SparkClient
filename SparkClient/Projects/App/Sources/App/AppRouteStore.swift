import Combine
import Foundation

@MainActor
final class AppRouteStore: ObservableObject {
    enum RootTab: Int, Hashable {
        case home = 0
        /// 历史版本曾为「健康」Tab；保留 raw value 以免升级后 Tab 顺序错乱。
        case knowledge = 2
        case chat = 3
        case settings = 4
    }

    @Published var selectedTab: RootTab = .home

    func resetForNewSession() {
        selectedTab = .home
    }
}
