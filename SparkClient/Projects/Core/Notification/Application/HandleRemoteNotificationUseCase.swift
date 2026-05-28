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
        case "member_invite", "member-invite":
            let inviteID = (userInfo["invite_id"] as? String).flatMap(Int.init)
                ?? (userInfo["invite_id"] as? Int)
                ?? (userInfo["inviteId"] as? String).flatMap(Int.init)
                ?? (userInfo["inviteId"] as? Int)
            if let inviteID {
                return .memberInvite(inviteID: inviteID)
            }
            return .home
        default:
            return nil
        }
    }

    private static func extractInviteID(_ userInfo: [AnyHashable: Any]) -> Int? {
        (userInfo["invite_id"] as? String).flatMap(Int.init)
            ?? (userInfo["invite_id"] as? Int)
            ?? (userInfo["inviteId"] as? String).flatMap(Int.init)
            ?? (userInfo["inviteId"] as? Int)
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
        if payload.type == "ai_trial_application_result" {
            NotificationCenter.default.post(name: .aiTrialApplicationResultReceived, object: nil)
            let tapPayload = payload
            let coordinator = routeCoordinator
            switch entryPoint {
            case .foreground:
                notificationClient.publish(
                    NotificationIntent(
                        title: payload.title ?? "试用申请结果",
                        message: payload.body,
                        level: .info,
                        presentation: .banner,
                        dedupeKey: "ai_trial_application_result",
                        source: payload.source,
                        onTap: { [weak coordinator] in
                            coordinator?.routeRemoteNotification(
                                tapPayload,
                                entryPoint: .interaction(actionIdentifier: "ai_trial_application_result_tap")
                            )
                        }
                    )
                )
            case .interaction:
                routeCoordinator.routeRemoteNotification(payload, entryPoint: entryPoint)
            }
            return
        }

        // Special-case member_invite: foreground = tappable banner; tap = route.
        if payload.type == "member_invite", let route = payload.route,
           case .memberInvite(let inviteID) = route {
            switch entryPoint {
            case .foreground:
                NotificationCenter.default.post(name: .memberInvitePendingRefresh, object: nil)
                let tapPayload = payload
                let coordinator = routeCoordinator
                notificationClient.publish(
                    NotificationIntent(
                        title: payload.title ?? L10n.text("home.members.invite.title"),
                        message: payload.body,
                        level: .info,
                        presentation: .banner,
                        dedupeKey: "member_invite_\(inviteID)",
                        source: payload.source,
                        onTap: { [weak coordinator] in
                            coordinator?.routeRemoteNotification(
                                tapPayload,
                                entryPoint: .interaction(actionIdentifier: "member_invite_tap")
                            )
                        }
                    )
                )
            case .interaction:
                routeCoordinator.routeRemoteNotification(payload, entryPoint: entryPoint)
            }
            return
        }

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
