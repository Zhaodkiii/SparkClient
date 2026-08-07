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
        case .home, .homeMedicalList, .homeFamilyMedicineCabinet:
            return .home
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
    }

    @Published var selectedTab: RootTab = .home
    @Published private(set) var routeStacks: [RootTab: [AppRoute]] = [:]

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

    func resetRouteGraph() {
        selectedTab = .home
        routeStacks.removeAll()
    }
}
