import Foundation

enum RemoteNotificationEntryPoint: Sendable {
    case foreground
    case interaction(actionIdentifier: String)
}

struct RemoteNotificationPayload: Sendable {
    var title: String?
    var body: String
    var type: String?
    var route: AppRoute?
    var source: String

    static func from(userInfo: [AnyHashable: Any], fallbackTitle: String?, fallbackBody: String) -> RemoteNotificationPayload {
        let type = userInfo["type"] as? String
        let route = Self.mapRoute(userInfo)

        return RemoteNotificationPayload(
            title: fallbackTitle,
            body: fallbackBody,
            type: type,
            route: route,
            source: "push"
        )
    }

    private static func mapRoute(_ userInfo: [AnyHashable: Any]) -> AppRoute? {
        let rawRoute = (userInfo["route"] as? String)?.lowercased()
        let rawTab = (userInfo["route_tab"] as? String)?.lowercased()
        let threadID = (userInfo["thread_id"] as? String)
            .flatMap(UUID.init(uuidString:))
            ?? (userInfo["threadID"] as? String).flatMap(UUID.init(uuidString:))

        switch rawRoute ?? rawTab {
        case "home", "health":
            return .home
        case "knowledge":
            return .knowledge
        case "chat":
            if let threadID {
                return .chatThread(threadID)
            }
            return .chatList
        case "settings":
            return .settings
        case "ai_settings", "ai-settings", "settings/ai":
            return .aiSettings
        default:
            return nil
        }
    }
}

@MainActor
struct HandleRemoteNotificationUseCase {
    private let routeCoordinator: any RouteCoordinating
    private let notificationClient: any NotificationClient

    init(routeCoordinator: any RouteCoordinating, notificationClient: any NotificationClient) {
        self.routeCoordinator = routeCoordinator
        self.notificationClient = notificationClient
    }

    func execute(payload: RemoteNotificationPayload, entryPoint: RemoteNotificationEntryPoint) {
        routeCoordinator.routeRemoteNotification(payload, entryPoint: entryPoint)

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
