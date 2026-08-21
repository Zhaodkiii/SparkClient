import Combine
import Foundation

/// 根 Tab 的设备级偏好。它只负责读写最后选中的 Tab，不参与路由栈管理。
@MainActor
final class RootTabPreferenceStore: ObservableObject {
    static let storageKey = "app.route.selectedRootTab"

    @Published var selectedTab: AppRouteStore.RootTab {
        didSet {
            guard selectedTab != oldValue else { return }
            userDefaults.set(selectedTab.rawValue, forKey: Self.storageKey)
        }
    }

    private let userDefaults: UserDefaults

    init(
        userDefaults: UserDefaults = .standard,
        defaultTab: AppRouteStore.RootTab = AppRouteStore.defaultRootTab
    ) {
        self.userDefaults = userDefaults
        if let rawValue = userDefaults.object(forKey: Self.storageKey) as? Int,
           let tab = AppRouteStore.RootTab(rawValue: rawValue) {
            selectedTab = tab
        } else {
            selectedTab = defaultTab
        }
    }
}
