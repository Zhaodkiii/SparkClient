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
    var inviteID: Int?
    var source: String
    var envelope: NotificationEnvelope?

    static func from(userInfo: [AnyHashable: Any], fallbackTitle: String?, fallbackBody: String) -> RemoteNotificationPayload {
        let envelope = NotificationEnvelopeDecoder.decode(userInfo: userInfo)
        let compatibility = Self.compatibilityValues(from: envelope)
        let type = compatibility.type ?? userInfo["type"] as? String
        let inviteID = compatibility.inviteID ?? extractInviteID(userInfo)
        let route = compatibility.route ?? Self.mapRoute(userInfo)

        return RemoteNotificationPayload(
            title: fallbackTitle,
            body: fallbackBody,
            type: type,
            route: route,
            inviteID: inviteID,
            source: "push",
            envelope: envelope
        )
    }

    private static func compatibilityValues(from envelope: NotificationEnvelope?) -> (type: String?, inviteID: Int?, route: AppRoute?) {
        guard let envelope, envelope.canExecuteAction else { return (nil, nil, nil) }
        switch NotificationActionRouter().destination(for: envelope) {
        case .proTrial: return ("ai_trial_application_result", nil, .aiSettings)
        case .memberInvite(let id): return ("member_invite", Int(id), nil)
        case .medicalResource: return ("health_resource_changed", nil, nil)
        case .appUpdate: return (nil, nil, .settings)
        case .notificationCenter, .member, .medicationPlan, .task: return (nil, nil, nil)
        }
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
            return nil
        default:
            return nil
        }
    }

    static func extractInviteID(_ userInfo: [AnyHashable: Any]) -> Int? {
        (userInfo["invite_id"] as? String).flatMap(Int.init)
            ?? (userInfo["invite_id"] as? Int)
            ?? (userInfo["inviteId"] as? String).flatMap(Int.init)
            ?? (userInfo["inviteId"] as? Int)
    }
}

@MainActor
struct HandleRemoteNotificationUseCase {
    private let routeCoordinator: any RouteCoordinating
    private let launchIntentCoordinator: LaunchIntentCoordinator
    private let notificationClient: any NotificationClient

    init(
        routeCoordinator: any RouteCoordinating,
        launchIntentCoordinator: LaunchIntentCoordinator,
        notificationClient: any NotificationClient
    ) {
        self.routeCoordinator = routeCoordinator
        self.launchIntentCoordinator = launchIntentCoordinator
        self.notificationClient = notificationClient
    }

    func execute(
        payload: RemoteNotificationPayload,
        entryPoint: RemoteNotificationEntryPoint,
        notificationRequestID: String? = nil,
        rawUserInfo: [AnyHashable: Any]? = nil
    ) {
        if let rawUserInfo,
           let medicationPayload = MedicationReminderPayloadParser.parse(userInfo: rawUserInfo) {
            handleMedicationReminder(
                payload: medicationPayload,
                entryPoint: entryPoint,
                notificationRequestID: notificationRequestID,
                bannerTitle: payload.title,
                bannerBody: payload.body
            )
            return
        }

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

        if payload.type == "health_resource_changed", let rawUserInfo {
            handleHealthResourceChanged(
                userInfo: rawUserInfo,
                entryPoint: entryPoint,
                notificationRequestID: notificationRequestID,
                payload: payload
            )
            return
        }

        if payload.type == "member_invite", let inviteID = payload.inviteID {
            switch entryPoint {
            case .foreground:
                NotificationCenter.default.post(name: .memberInvitePendingRefresh, object: nil)
                let tapInviteID = inviteID
                let intentCoordinator = launchIntentCoordinator
                notificationClient.publish(
                    NotificationIntent(
                        title: payload.title ?? L10n.text("home.members.invite.title"),
                        message: payload.body,
                        level: .info,
                        presentation: .banner,
                        dedupeKey: "member_invite_\(inviteID)",
                        source: payload.source,
                        onTap: { [weak intentCoordinator] in
                            intentCoordinator?.receive(
                                .memberInviteFromPush(
                                    MemberInvitePushLaunchIntent(
                                        id: UUID(),
                                        inviteID: tapInviteID,
                                        receivedAt: Date(),
                                        source: .inAppNotificationBannerTap,
                                        actionIdentifier: "member_invite_tap",
                                        notificationRequestID: nil
                                    )
                                )
                            )
                        }
                    )
                )
            case .interaction(let actionIdentifier):
                receiveMemberInvitePushIntent(
                    inviteID: inviteID,
                    source: .remoteNotificationInteraction,
                    actionIdentifier: actionIdentifier,
                    notificationRequestID: notificationRequestID
                )
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

    private func receiveMemberInvitePushIntent(
        inviteID: Int,
        source: LaunchIntentSource,
        actionIdentifier: String,
        notificationRequestID: String?
    ) {
        launchIntentCoordinator.receive(
            .memberInviteFromPush(
                MemberInvitePushLaunchIntent(
                    id: UUID(),
                    inviteID: inviteID,
                    receivedAt: Date(),
                    source: source,
                    actionIdentifier: actionIdentifier,
                    notificationRequestID: notificationRequestID
                )
            )
        )
    }

    private func handleMedicationReminder(
        payload: MedicationReminderLaunchPayload,
        entryPoint: RemoteNotificationEntryPoint,
        notificationRequestID: String?,
        bannerTitle: String?,
        bannerBody: String
    ) {
        switch entryPoint {
        case .foreground:
            let tapPayload = payload
            let intentCoordinator = launchIntentCoordinator
            notificationClient.publish(
                NotificationIntent(
                    title: bannerTitle ?? "用药提醒",
                    message: bannerBody,
                    level: .info,
                    presentation: .banner,
                    dedupeKey: payload.notificationID,
                    source: "medication_reminder",
                    onTap: { [weak intentCoordinator] in
                        intentCoordinator?.receive(
                            .medicationReminder(
                                MedicationReminderLaunchIntent(
                                    id: UUID(),
                                    payload: tapPayload,
                                    receivedAt: Date(),
                                    source: .inAppNotificationBannerTap,
                                    notificationRequestID: nil
                                )
                            )
                        )
                    }
                )
            )
        case .interaction:
            receiveMedicationReminderIntent(
                payload: payload,
                source: .localNotificationInteraction,
                notificationRequestID: notificationRequestID
            )
        }
    }

    private func receiveMedicationReminderIntent(
        payload: MedicationReminderLaunchPayload,
        source: LaunchIntentSource,
        notificationRequestID: String?
    ) {
        launchIntentCoordinator.receive(
            .medicationReminder(
                MedicationReminderLaunchIntent(
                    id: UUID(),
                    payload: payload,
                    receivedAt: Date(),
                    source: source,
                    notificationRequestID: notificationRequestID
                )
            )
        )
    }

    private func handleHealthResourceChanged(
        userInfo: [AnyHashable: Any],
        entryPoint: RemoteNotificationEntryPoint,
        notificationRequestID: String?,
        payload: RemoteNotificationPayload
    ) {
        let envelopeValues: (memberID: Int, resourceType: String, resourceID: Int)? = {
            guard case let .openMedicalResource(member, resourceType, resource) = payload.envelope?.action,
                  let memberID = Int(member), let resourceID = Int(resource) else { return nil }
            return (memberID, resourceType, resourceID)
        }()
        let memberID = envelopeValues?.memberID
            ?? (userInfo["member_id"] as? String).flatMap(Int.init)
            ?? (userInfo["member_id"] as? Int)
        guard let memberID else { return }

        let resourceType = envelopeValues?.resourceType
            ?? userInfo["resource_type"] as? String
            ?? "medication_plan"
        let resourceID = envelopeValues?.resourceID
            ?? (userInfo["resource_id"] as? String).flatMap(Int.init)
            ?? (userInfo["resource_id"] as? Int)
        let action = userInfo["action"] as? String ?? "updated"

        switch entryPoint {
        case .foreground:
            let intentCoordinator = launchIntentCoordinator
            notificationClient.publish(
                NotificationIntent(
                    title: payload.title ?? L10n.text("notification.health_resource_changed.medication_plan.title"),
                    message: payload.body,
                    level: .info,
                    presentation: .banner,
                    dedupeKey: "health_resource_changed_\(memberID)_\(resourceID ?? 0)",
                    source: payload.source,
                    onTap: { [intentCoordinator] in
                        intentCoordinator.receive(
                            .healthResourceChanged(
                                HealthResourceChangedLaunchIntent(
                                    id: UUID(),
                                    memberID: memberID,
                                    resourceType: resourceType,
                                    resourceID: resourceID,
                                    action: action,
                                    receivedAt: Date(),
                                    source: .inAppNotificationBannerTap,
                                    notificationRequestID: nil
                                )
                            )
                        )
                    }
                )
            )
        case .interaction:
            receiveHealthResourceChangedIntent(
                memberID: memberID,
                resourceType: resourceType,
                resourceID: resourceID,
                action: action,
                source: .remoteNotificationInteraction,
                notificationRequestID: notificationRequestID
            )
        }
    }

    private func receiveHealthResourceChangedIntent(
        memberID: Int,
        resourceType: String,
        resourceID: Int?,
        action: String,
        source: LaunchIntentSource,
        notificationRequestID: String?
    ) {
        launchIntentCoordinator.receive(
            .healthResourceChanged(
                HealthResourceChangedLaunchIntent(
                    id: UUID(),
                    memberID: memberID,
                    resourceType: resourceType,
                    resourceID: resourceID,
                    action: action,
                    receivedAt: Date(),
                    source: source,
                    notificationRequestID: notificationRequestID
                )
            )
        )
    }
}
