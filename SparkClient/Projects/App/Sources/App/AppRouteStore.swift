import Combine
import Foundation
import SwiftUI

/// App 级路由目标：通知、深链、登录态变化最终都先解析成这里的 typed route。
enum AppRoute: Hashable, Sendable {
    case home
    case knowledge
    case nutrition
    case fitness
    case chatList
    case chatThread(UUID)
    /// 对话 Tab 首次自动进入的会话；返回按钮应回到健康首页，而不是会话列表。
    case automaticChatThread(UUID)
    case deepTutorList
    case deepTutorThread(UUID)
    case popularScience
    case popularScienceArticle(id: Int)
    case settings
    case aiSettings
    case accountManagement
    /// 首页医疗卡片对应的列表/执行中心页。
    case homeMedicalList(HomeMedicalListRoute, MedicationExecutionInitialFocus?)
    /// 首页家庭药箱入口。
    case homeFamilyMedicineCabinet(memberID: Int)
    case taskDetail(memberID: Int, taskID: Int)

    var rootTab: AppRouteStore.RootTab {
        switch self {
        case .home, .homeMedicalList, .homeFamilyMedicineCabinet, .taskDetail:
            return .healthHome
        case .knowledge:
            return .knowledge
        case .nutrition:
            return .nutrition
        case .fitness:
            return .fitness
        case .chatList, .chatThread, .automaticChatThread:
            return .chat
        case .deepTutorList, .deepTutorThread:
            return .deepTutor
        case .popularScience, .popularScienceArticle:
            return .popularScience
        case .settings, .aiSettings, .accountManagement:
            return .settings
        }
    }

    var isRootDestination: Bool {
        switch self {
        case .home, .knowledge, .nutrition, .fitness, .chatList, .popularScience, .settings, .deepTutorList:
            return true
        case .chatThread, .automaticChatThread, .popularScienceArticle, .aiSettings, .accountManagement, .homeMedicalList, .homeFamilyMedicineCabinet, .taskDetail, .deepTutorThread:
            return false
        }
    }
}

@MainActor
final class AppRouteStore: ObservableObject {
    enum RootTab: Int, Hashable {
        /// 统一健康首页（医疗档案等），由 `HealthHomeView` 承载。
        case healthHome = 0
        case knowledge = 2
        case chat = 3
        case settings = 4
        /// 科普 Tab 使用新 raw value，避免影响历史 settings 选中态。
        case popularScience = 5
        /// DeepTutor Tab 使用新 raw value，避免影响历史 Tab 选中态。
        case deepTutor = 6
        /// iOS 26 专用搜索 Tab。
        case search = 7
        /// 饮食营养 Tab，使用新 raw value，避免影响历史 Tab 选中态。
        case nutrition = 8
        /// 运动健康 Tab，使用新 raw value，避免影响历史 Tab 选中态。
        case fitness = 9
    }

    private let preferenceStore: RootTabPreferenceStore

    /// 用户/程序化路由切换根 tab 后自动持久化；下次冷启动通过 `init(storage:)` 恢复。
    @Published var selectedTab: RootTab {
        didSet {
            guard selectedTab != oldValue else { return }
            preferenceStore.selectedTab = selectedTab
        }
    }

    @Published private(set) var routeStacks: [RootTab: [AppRoute]] = [:]

    static var defaultRootTab: RootTab {
        .healthHome
    }

    init(storage: UserDefaults = .standard) {
        let preferenceStore = RootTabPreferenceStore(userDefaults: storage)
        self.preferenceStore = preferenceStore
        selectedTab = preferenceStore.selectedTab
    }

    /// 从 storage 恢复上次选中的根 tab；无值或 rawValue 失效时回退默认 tab。
    /// 使用 `object(forKey:)` 区分"未设置"与 rawValue = 0。
    static func restoreSelectedTab(from storage: UserDefaults) -> RootTab {
        RootTabPreferenceStore(userDefaults: storage).selectedTab
    }

    /// 当前 selectedTab 在给定容器布局中不可见时兜底：优先默认 tab（.chat），
    /// 否则取第一个可见 tab；兜底结果会写回持久化，避免下次继续恢复非法 tab。
    func ensureSelectedTabIsVisible(visibleTabs: Set<RootTab>) {
        guard visibleTabs.contains(selectedTab) == false else { return }
        let fallback = visibleTabs.contains(Self.defaultRootTab)
            ? Self.defaultRootTab
            : (visibleTabs.first ?? Self.defaultRootTab)
        selectedTab = fallback
    }

    func routes(for tab: RootTab) -> [AppRoute] {
        routeStacks[tab, default: []]
    }

    func navigationPath(for tab: RootTab) -> NavigationPath {
        NavigationPath(routes(for: tab))
    }

    func route(to route: AppRoute, replaceStack: Bool = false) {
        let tab = route.rootTab
        selectedTab = tab
        if route.isRootDestination {
            routeStacks[tab] = replaceStack ? [] : routeStacks[tab, default: []]
            return
        }

        if replaceStack {
            routeStacks[tab] = [route]
        } else {
            var stack = routeStacks[tab, default: []]
            if stack.last != route {
                stack.append(route)
            }
            routeStacks[tab] = stack
        }
    }

    func replaceStack(_ routes: [AppRoute], for tab: RootTab) {
        routeStacks[tab] = routes
        selectedTab = tab
    }

    /// 清理当前账号的导航栈，但保留设备级最后选中 Tab。
    /// 账号切换/退出登录不应覆盖用户下次冷启动的入口偏好。
    func resetRouteGraph() {
        routeStacks.removeAll()
    }
}
