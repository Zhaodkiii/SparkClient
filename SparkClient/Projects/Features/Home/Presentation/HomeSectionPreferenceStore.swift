import Combine
import Foundation

/// 首页分页停留位置（UserDefaults 持久化）。下次打开恢复到用户上次停留的分页，默认工作台。
@MainActor
final class HomeSectionPreferenceStore: ObservableObject {
    static let shared = HomeSectionPreferenceStore()

    @Published var section: IOS26HomeView.HomeSection {
        didSet {
            guard section != oldValue else { return }
            userDefaults.set(section.rawValue, forKey: storageKey)
        }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "spark.home.last_section"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let raw = userDefaults.string(forKey: storageKey),
           let section = IOS26HomeView.HomeSection(rawValue: raw) {
            self.section = section
        } else {
            self.section = .dashboard
        }
    }
}
