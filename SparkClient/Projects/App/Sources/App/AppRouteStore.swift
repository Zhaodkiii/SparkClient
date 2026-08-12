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

    var rootTab: AppRouteStore.RootTab {
        switch self {
        case .home:
            return .home
        case .homeMedicalList, .homeFamilyMedicineCabinet:
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
        case .chatThread, .popularScienceArticle, .aiSettings, .accountManagement, .homeMedicalList, .homeFamilyMedicineCabinet, .deepTutorThread:
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
        /// 传统健康首页（医疗档案、营养等），由 `HealthHomeView` / 旧 `HomeView` 承载。
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
    /// iOS 26 工作台发起的设置与医疗子页由 `.home` 栈独立承载，经典系统继续复用传统 `.health` / `.settings` 栈。
    private func hostTab(for route: AppRoute) -> RootTab {
        switch route {
        case .home:
            return Self.supportsIOS26Home ? .home : .health
        case .homeMedicalList, .homeFamilyMedicineCabinet:
            return Self.supportsIOS26Home ? .home : .health
        case .settings, .aiSettings, .accountManagement:
            return Self.supportsIOS26Home ? .home : .settings
        default:
            return route.rootTab
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
