import Foundation

enum RemoteNotificationEntryPoint: Sendable {
    case foreground
    case interaction(actionIdentifier: String)
}

struct RemoteNotificationPayload: Sendable {
    var title: String?
    var body: String
    var type: String?
    var routeTab: AppRouteStore.RootTab?
    var source: String

    static func from(userInfo: [AnyHashable: Any], fallbackTitle: String?, fallbackBody: String) -> RemoteNotificationPayload {
        let type = userInfo["type"] as? String
        let routeTab = (userInfo["route_tab"] as? String).flatMap(Self.mapRouteTab)

        return RemoteNotificationPayload(
            title: fallbackTitle,
            body: fallbackBody,
            type: type,
            routeTab: routeTab,
            source: "push"
        )
    }

    private static func mapRouteTab(_ raw: String) -> AppRouteStore.RootTab? {
        switch raw.lowercased() {
        case "home":
            return .home
        case "health":
            return .health
        case "chat":
            return .chat
        case "settings":
            return .settings
        default:
            return nil
        }
    }
}

@MainActor
struct HandleRemoteNotificationUseCase {
    private let routeStore: AppRouteStore
    private let notificationClient: any NotificationClient

    init(routeStore: AppRouteStore, notificationClient: any NotificationClient) {
        self.routeStore = routeStore
        self.notificationClient = notificationClient
    }

    func execute(payload: RemoteNotificationPayload, entryPoint: RemoteNotificationEntryPoint) {
        if case .interaction = entryPoint, let tab = payload.routeTab {
            routeStore.selectedTab = tab
        }

        switch payload.type {
        case "success":
            notificationClient.success(payload.body, title: payload.title, source: payload.source)
        case "warning":
            notificationClient.warning(payload.body, title: payload.title, source: payload.source)
        case "error":
            notificationClient.error(payload.body, title: payload.title, source: payload.source)
        default:
            // 前台默认使用 Banner，交互默认使用 Toast。
            let presentation: NotificationPresentation = {
                switch entryPoint {
                case .foreground:
                    return .banner
                case .interaction:
                    return .toast
                }
            }()
            notificationClient.publish(
                NotificationIntent(
                    title: payload.title,
                    message: payload.body,
                    level: .info,
                    presentation: presentation,
                    dedupeKey: payload.type,
                    source: payload.source
                )
            )
        }
    }
}
