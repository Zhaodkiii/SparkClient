import Combine
import Foundation
import UIKit

@MainActor
protocol RouteCoordinating: AnyObject {
    func routeRemoteNotification(_ payload: RemoteNotificationPayload, entryPoint: RemoteNotificationEntryPoint)
}

/// 统一路由协调器：通知、深链、系统生命周期和登录态变化先进入这里，再写入 typed route graph。
@MainActor
final class RouteCoordinator: ObservableObject, RouteCoordinating {
    private let routeStore: AppRouteStore
    private let logger: Logger
    private weak var lifecycle: AppLifecycleCoordinator?
    private weak var sessionStore: AppSessionStore?
    private var cancellables: Set<AnyCancellable> = []
    private var sessionCancellable: AnyCancellable?
    private var didStartSystemRouting = false
    private var lastSessionAccountID: Int64?

    init(routeStore: AppRouteStore, logger: Logger = ConsoleLogger()) {
        self.routeStore = routeStore
        self.logger = logger
        logger.info("RouteCoordinator 已初始化：通知/深链/登录态统一进入 typed route graph", module: .general)
    }

    func bind(lifecycle: AppLifecycleCoordinator, sessionStore: AppSessionStore) {
        self.lifecycle = lifecycle
        self.sessionStore = sessionStore
        observeSessionState(sessionStore)
    }

    func startSystemEventRouting() {
        guard didStartSystemRouting == false else { return }
        didStartSystemRouting = true

        NotificationCenter.default.publisher(for: AuthSessionInvalidation.notificationName)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                let message = notification.userInfo?["message"] as? String ?? ""
                Task { @MainActor in
                    await self?.handleServerAuthInvalidation(invalidationMessage: message)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleForegroundEntry()
                }
            }
            .store(in: &cancellables)

        logger.info("RouteCoordinator 已接管系统事件：鉴权失效、前台恢复", module: .general)
    }

    func handleDeepLink(_ url: URL) {
        guard let route = AppRoute(url: url) else {
            logger.warning("路由流程：无法识别深链 url=\(url.absoluteString)", module: .general)
            return
        }

        logger.info("路由流程：消费深链 route=\(route)", module: .general)
        routeStore.route(to: route, replaceStack: true)
    }

    func routeRemoteNotification(_ payload: RemoteNotificationPayload, entryPoint: RemoteNotificationEntryPoint) {
        guard case .interaction = entryPoint else { return }
        guard let route = payload.route else { return }

        logger.info("路由流程：消费远程通知 route=\(route)", module: .push)
        routeStore.route(to: route, replaceStack: true)
    }

    func resetRouteGraphForAccountRuntime(reason: String) {
        logger.info("路由流程：重置账号级 route graph reason=\(reason)", module: .general)
        routeStore.resetRouteGraph()
    }

    private func observeSessionState(_ sessionStore: AppSessionStore) {
        sessionCancellable = sessionStore.$state
            .removeDuplicates()
            .sink { [weak self] state in
                Task { @MainActor in
                    self?.consumeSessionState(state)
                }
            }
    }

    private func consumeSessionState(_ state: AppSessionStore.State) {
        switch state {
        case .loading:
            logger.debug("路由流程：登录态 loading，暂不改动 route graph", module: .auth)
        case .signedOut:
            lastSessionAccountID = nil
            resetRouteGraphForAccountRuntime(reason: "signedOut")
        case .signedIn(let session):
            guard lastSessionAccountID != session.accountID else { return }
            lastSessionAccountID = session.accountID
            logger.info("路由流程：登录态切换到账号 accountID=\(session.accountID)", module: .auth)
        }
    }

    private func handleForegroundEntry() async {
        logger.debug("路由流程：收到前台恢复事件，交给生命周期协调器同步业务", module: .general)
        await lifecycle?.syncForegroundWorkIfNeeded()
    }

    private func handleServerAuthInvalidation(invalidationMessage: String) async {
        logger.warning("路由流程：收到服务端鉴权失效事件，交给生命周期协调器处理", module: .auth)
        await lifecycle?.handleServerAuthInvalidationIfNeeded(invalidationMessage: invalidationMessage)
    }
}

private extension AppRoute {
    init?(url: URL) {
        let host = url.host?.lowercased()
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let target = [host, path].compactMap { $0 }.joined(separator: "/")

        if target.contains("knowledge") {
            self = .knowledge
            return
        }
        if target.contains("settings/ai") || target.contains("ai-settings") {
            self = .aiSettings
            return
        }
        if target.contains("settings") {
            self = .settings
            return
        }
        if target.contains("chat") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let thread = components.queryItems?.first(where: { $0.name == "threadID" || $0.name == "thread_id" })?.value,
               let threadID = UUID(uuidString: thread) {
                self = .chatThread(threadID)
            } else {
                self = .chatList
            }
            return
        }
        if target.contains("member-invite") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let idValue = components.queryItems?.first(where: { $0.name == "id" })?.value,
               let inviteID = Int(idValue) {
                PendingMemberInviteStore.save(inviteID: inviteID)
            }
            self = .home
            return
        }
        if target.contains("member-share") {
            if let ticket = MemberShareDeepLinkParser.ticket(from: url) {
                PendingMemberShareTicketStore.save(ticket)
            }
            self = .home
            return
        }
        if target.contains("home") {
            self = .home
            return
        }
        return nil
    }
}
