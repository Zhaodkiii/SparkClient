import Combine
import Foundation
import SwiftUI

/// App 级路由目标：通知、深链、登录态变化最终都先解析成这里的 typed route。
enum AppRoute: Hashable, Sendable {
    case home
    case knowledge
    case chatList
    case chatThread(UUID)
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
        case .home:
            return .home
        case .homeMedicalList, .homeFamilyMedicineCabinet, .taskDetail:
            return .health
        case .knowledge:
            return .knowledge
        case .chatList, .chatThread:
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
        case .home, .knowledge, .chatList, .popularScience, .settings, .deepTutorList:
            return true
        case .chatThread, .popularScienceArticle, .aiSettings, .accountManagement, .homeMedicalList, .homeFamilyMedicineCabinet, .taskDetail, .deepTutorThread:
            return false
        }
    }
}

@MainActor
final class AppRouteStore: ObservableObject {
    enum RootTab: Int, Hashable {
        /// iOS 26 新工作台首页。经典系统没有独立工作台，`.home` 路由会落到 `.health`。
        case home = 0
        /// 历史版本曾为「健康」Tab；保留 raw value 以免升级后 Tab 顺序错乱。
        case knowledge = 2
        case chat = 3
        case settings = 4
        /// 科普 Tab 使用新 raw value，避免影响历史 settings 选中态。
        case popularScience = 5
        /// DeepTutor Tab 使用新 raw value，避免影响历史 Tab 选中态。
        case deepTutor = 6
        /// iOS 26 专用搜索 Tab。
        case search = 7
        /// 传统健康首页（医疗档案、营养等），由 `HealthHomeView` 承载。
        case health = 8
    }

    @Published var selectedTab: RootTab = AppRouteStore.defaultRootTab
    @Published private(set) var routeStacks: [RootTab: [AppRoute]] = [:]

    static var defaultRootTab: RootTab {
        supportsIOS26Home ? .home : .health
    }

    static var supportsIOS26Home: Bool {
        if #available(iOS 26.0, *) {
            return true
        } else {
            return false
        }
    }

    func routes(for tab: RootTab) -> [AppRoute] {
        routeStacks[tab, default: []]
    }

    func navigationPath(for tab: RootTab) -> NavigationPath {
        NavigationPath(routes(for: tab))
    }

    func route(to route: AppRoute, replaceStack: Bool = false) {
        let tab = hostTab(for: route)
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

    /// `.home` 是 iOS 26 工作台；经典系统没有独立工作台，落到健康首页。
    /// iOS 26 下若当前已在 `.home` / `.health` 宿主栈内，则优先沿当前宿主继续 push；
    /// 否则再回退到默认承载链路，避免工作台与健康页互相串栈。
    private func hostTab(for route: AppRoute) -> RootTab {
        switch route {
        case .home:
            return Self.supportsIOS26Home ? .home : .health
        case .homeMedicalList, .homeFamilyMedicineCabinet, .taskDetail:
            return currentHomeHostTab(default: Self.supportsIOS26Home ? .home : .health)
        case .settings, .aiSettings, .accountManagement:
            return currentHomeHostTab(default: Self.supportsIOS26Home ? .home : .settings)
        default:
            return route.rootTab
        }
    }

    private func currentHomeHostTab(default fallback: RootTab) -> RootTab {
        switch selectedTab {
        case .home, .health:
            return selectedTab
        default:
            return fallback
        }
    }

    func replaceStack(_ routes: [AppRoute], for tab: RootTab) {
        routeStacks[tab] = routes
        selectedTab = tab
    }

    func resetRouteGraph() {
        selectedTab = Self.defaultRootTab
        routeStacks.removeAll()
    }
}
