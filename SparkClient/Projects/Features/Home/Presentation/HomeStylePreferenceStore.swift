import Combine
import Foundation

/// 首页样式（控制健康 Tab 承载传统首页还是 iOS 26 新款首页分页）。
enum HomeStyle: String, CaseIterable, Identifiable {
    /// 新款首页：健康 Tab 承载 `IOS26HomeView`（新款首页/饮食营养/运动健康三页 pager），隐藏底部独立饮食与运动 Tab。
    case dashboard
    /// 传统首页：健康 Tab 承载 `HealthHomeView`，保留底部独立饮食与运动 Tab。
    case classic

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .dashboard:
            return "settings.general.home_style.dashboard"
        case .classic:
            return "settings.general.home_style.classic"
        }
    }
}

/// 首页样式偏好（UserDefaults 持久化）。
@MainActor
final class HomeStylePreferenceStore: ObservableObject {
    static let shared = HomeStylePreferenceStore()

    @Published var style: HomeStyle {
        didSet {
            guard style != oldValue else { return }
            userDefaults.set(style.rawValue, forKey: storageKey)
        }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "spark.home.style"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let raw = userDefaults.string(forKey: storageKey),
           let style = HomeStyle(rawValue: raw) {
            self.style = style
        } else {
            self.style = .classic
        }
    }
}
