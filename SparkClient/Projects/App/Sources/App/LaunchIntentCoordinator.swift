import Combine
import Foundation

/// 首页宿主消费 handler 协议
@MainActor
protocol LaunchIntentHandling: AnyObject {
    func availability(for intent: LaunchIntent, hostState: LaunchIntentHostState) -> LaunchIntentAvailability
    func handle(
        _ intent: LaunchIntent,
        setActiveFullScreenCover: @escaping (HomeFullScreenCover?) -> Void
    ) async -> LaunchIntentConsumeResult
}

/// App 级冷启动目标页面公共调度器（APP-COLD-ROUTE-000001 / 000002）
@MainActor
final class LaunchIntentCoordinator: ObservableObject {
    /// 兼容只读：队列头部（优先级最高）意图
//    var pendingIntent: LaunchIntent? { sortedQueue().first?.intent }
    @Published private(set) var queueCount = 0
    @Published private(set) var queueRevision = 0
    @Published private(set) var readiness = LaunchIntentReadiness()
    @Published private(set) var hostState = LaunchIntentHostState()

    private let logger: Logger
    private let maxQueueSize = 20
    private var queue: [QueuedLaunchIntent] = []
    private var nextSequence: Int64 = 0
    private var consumedIntentIDs: Set<UUID> = []
    private(set) var activeIntent: QueuedLaunchIntent?
    private var isDraining = false

    init(logger: Logger) {
        self.logger = logger
    }

    func receive(_ intent: LaunchIntent) {
        if consumedIntentIDs.contains(intent.id) {
            logger.info(
                "LaunchIntent.discard id=\(intent.id) reason=already_consumed type=\(intent.logType)",
                module: .general
            )
            return
        }

        enqueue(intent)
    }

    func updateReadiness(_ transform: (inout LaunchIntentReadiness) -> Void) {
        let before = readiness
        transform(&readiness)
        guard before != readiness else { return }
        if readiness.canConsume {
            logger.debug(
                "LaunchIntent.readiness ready accountID=\(readiness.accountID.map(String.init) ?? "nil")",
                module: .general
            )
        } else if queue.isEmpty == false {
            logTopBlockedByReadiness()
        }
    }

    func updateHostState(_ transform: (inout LaunchIntentHostState) -> Void) {
        let before = hostState
        transform(&hostState)
        guard before != hostState else { return }
        logger.debug(
            "HomeHost.state activeSheet=\(hostState.activeSheetKind?.rawValue ?? "nil") cover=\(hostState.activeFullScreenCoverKind?.rawValue ?? "nil") uploadProcessing=\(hostState.isUploadProcessing)",
            module: .general
        )
    }

    func discardAll(reason: String) {
        for work in queue {
            logger.info(
                "LaunchIntent.discard id=\(work.id) reason=\(reason) type=\(work.intent.logType)",
                module: .general
            )
        }
        queue.removeAll()
        consumedIntentIDs.removeAll()
        activeIntent = nil
        hostState = LaunchIntentHostState()
        publishQueueState()
    }

    func requestDrain(
        reason: String,
        handler: any LaunchIntentHandling,
        setActiveFullScreenCover: @escaping (HomeFullScreenCover?) -> Void
    ) {
        logger.debug("LaunchIntent.drain.request reason=\(reason)", module: .general)
        Task {
            await runDrainLoop(
                handler: handler,
                setActiveFullScreenCover: setActiveFullScreenCover
            )
        }
    }

    private func runDrainLoop(
        handler: any LaunchIntentHandling,
        setActiveFullScreenCover: @escaping (HomeFullScreenCover?) -> Void
    ) async {
        guard isDraining == false else {
            logger.debug("LaunchIntent.drain.skip reason=already_draining", module: .general)
            return
        }
        isDraining = true
        defer { isDraining = false }

        while true {
            guard readiness.canConsume else {
                logTopBlockedByReadiness()
                return
            }

            guard let work = selectNextIntent() else {
                logger.debug("LaunchIntent.queue.empty", module: .general)
                return
            }

            let availability = handler.availability(for: work.intent, hostState: hostState)
            guard availability.canConsume else {
                markBlocked(workID: work.id, reason: availability.blockedReason ?? .homeHostNotReady)
                logger.info(
                    "LaunchIntent.drain.blocked id=\(work.id) reason=\(availability.blockedReason?.rawValue ?? "unknown")",
                    module: .general
                )
                return
            }

            activeIntent = work
            logger.info(
                "LaunchIntent.consume.start id=\(work.id) type=\(work.intent.logType)",
                module: .general
            )

            let result = await handler.handle(work.intent, setActiveFullScreenCover: setActiveFullScreenCover)

            switch result {
            case .consumed:
                removeFromQueue(workID: work.id)
                consumedIntentIDs.insert(work.id)
                logger.info(
                    "LaunchIntent.consume.success id=\(work.id) type=\(work.intent.logType)",
                    module: .general
                )

            case .notReady:
                markBlocked(workID: work.id, reason: .homeHostNotReady)
                activeIntent = nil
                return

            case .failedRecoverable(let reason):
                markBlocked(workID: work.id, reason: reason)
                activeIntent = nil
                logger.warning(
                    "LaunchIntent.consume.recoverable id=\(work.id) type=\(work.intent.logType) reason=\(reason.rawValue)",
                    module: .general
                )
                return

            case .failedTerminal(let reason):
                removeFromQueue(workID: work.id)
                consumedIntentIDs.insert(work.id)
                activeIntent = nil
                logger.warning(
                    "LaunchIntent.consume.terminal id=\(work.id) type=\(work.intent.logType) reason=\(reason.rawValue)",
                    module: .general
                )
            }

            activeIntent = nil
            publishQueueState()
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
    }

    private func enqueue(_ intent: LaunchIntent) {
        switch coalescingAction(for: intent) {
        case .dropIncoming:
            logger.info(
                "LaunchIntent.discard id=\(intent.id) reason=coalesce_drop type=\(intent.logType)",
                module: .general
            )
            return

        case .updateExisting(let index):
            let existing = queue[index]
            queue[index] = QueuedLaunchIntent(intent: intent, sequence: existing.sequence, enqueuedAt: existing.enqueuedAt)
            logger.info(
                "LaunchIntent.queue.coalesce action=updateExisting id=\(intent.id) existing=\(existing.id) type=\(intent.logType)",
                module: .general
            )

        case .replaceExisting:
            let removed = queue.filter { item in
                if case .medicalDocumentUpload = item.intent { return true }
                return false
            }
            queue.removeAll { item in
                if case .medicalDocumentUpload = item.intent { return true }
                return false
            }
            for item in removed {
                logger.info(
                    "LaunchIntent.queue.coalesce action=replaceExisting removed=\(item.id) incoming=\(intent.id)",
                    module: .general
                )
            }
            appendNew(intent)

        case .keepBoth:
            appendNew(intent)
        }

        sortQueue()
        enforceCapacity()
        publishQueueState()

        logger.info(
            "LaunchIntent.enqueue id=\(intent.id) type=\(intent.logType) priority=\(intent.priority) sequence=\(queue.last?.sequence ?? -1) source=\(intent.logSource)",
            module: .general
        )
        logger.debug("LaunchIntent.queue.sorted count=\(queue.count)", module: .general)

        if readiness.canConsume == false {
            logPendingIfBlocked(intentID: intent.id)
        }
    }

    private func coalescingAction(for incoming: LaunchIntent) -> LaunchIntentCoalescingAction {
        if let inviteID = incoming.memberInviteID,
           let index = queue.firstIndex(where: { $0.intent.memberInviteID == inviteID }) {
            return .updateExisting(index: index)
        }

        if case .medicalDocumentUpload = incoming {
            if queue.contains(where: { if case .medicalDocumentUpload = $0.intent { return true }; return false }) {
                return .replaceExisting
            }
            return .keepBoth
        }

        if let routeSignature = incoming.appRouteSignature,
           let index = queue.firstIndex(where: { $0.intent.appRouteSignature == routeSignature }) {
            return .updateExisting(index: index)
        }

        if let notificationID = incoming.medicationReminderNotificationID,
           let index = queue.firstIndex(where: { $0.intent.medicationReminderNotificationID == notificationID }) {
            return .updateExisting(index: index)
        }

        if let notificationID = incoming.taskReminderNotificationID,
           let index = queue.firstIndex(where: { $0.intent.taskReminderNotificationID == notificationID }) {
            return .updateExisting(index: index)
        }

        return .keepBoth
    }

    private func appendNew(_ intent: LaunchIntent) {
        nextSequence += 1
        queue.append(QueuedLaunchIntent(intent: intent, sequence: nextSequence))
    }

    private func sortQueue() {
        queue.sort { lhs, rhs in
            if lhs.intent.priority != rhs.intent.priority {
                return lhs.intent.priority < rhs.intent.priority
            }
            return lhs.sequence < rhs.sequence
        }
    }

    private func sortedQueue() -> [QueuedLaunchIntent] {
        queue.sorted { lhs, rhs in
            if lhs.intent.priority != rhs.intent.priority {
                return lhs.intent.priority < rhs.intent.priority
            }
            return lhs.sequence < rhs.sequence
        }
    }

    private func selectNextIntent() -> QueuedLaunchIntent? {
        sortedQueue().first
    }

    private func enforceCapacity() {
        while queue.count > maxQueueSize {
            guard let dropIndex = queue.indices.max(by: { lhs, rhs in
                let left = queue[lhs]
                let right = queue[rhs]
                if left.intent.priority != right.intent.priority {
                    return left.intent.priority < right.intent.priority
                }
                return left.sequence < right.sequence
            }) else { break }

            let dropped = queue.remove(at: dropIndex)
            logger.info(
                "LaunchIntent.queue.drop reason=capacity_limit id=\(dropped.id) type=\(dropped.intent.logType)",
                module: .general
            )
        }
    }

    private func markBlocked(workID: UUID, reason: LaunchIntentBlockedReason) {
        guard let index = queue.firstIndex(where: { $0.id == workID }) else { return }
        queue[index].attemptCount += 1
        queue[index].lastBlockedReason = reason
        queue[index].lastTriedAt = Date()
        publishQueueState()
    }

    private func removeFromQueue(workID: UUID) {
        queue.removeAll { $0.id == workID }
        publishQueueState()
    }

    private func publishQueueState() {
        queueCount = queue.count
        queueRevision &+= 1
    }

    private func logTopBlockedByReadiness() {
        guard let work = selectNextIntent() else { return }
        logPendingIfBlocked(intentID: work.id)
    }

    private func logPendingIfBlocked(intentID: UUID) {
        guard readiness.canConsume == false else { return }
        let reason: String
        if readiness.isSignedIn == false {
            reason = "app_not_ready sessionState=signedOut"
        } else if readiness.isAccountPrepared == false {
            reason = "account_not_prepared accountID=\(readiness.accountID.map(String.init) ?? "nil")"
        } else if readiness.isOnboardingBlocking {
            reason = "onboarding_blocking"
        } else if readiness.mainTabReady == false {
            reason = "main_tab_not_ready"
        } else if readiness.homeHostReady == false {
            reason = "home_host_not_ready"
        } else {
            reason = "unknown"
        }
        logger.info("LaunchIntent.pending id=\(intentID) reason=\(reason)", module: .general)
    }
}

private extension LaunchIntent {
    var logType: String {
        switch self {
        case .medicalDocumentUpload:
            return "medicalDocumentUpload"
        case .memberInviteFromPush:
            return "memberInviteFromPush"
        case .medicationReminder:
            return "medicationReminder"
        case .taskReminder:
            return "taskReminder"
        case .healthResourceChanged:
            return "healthResourceChanged"
        case .appRoute:
            return "appRoute"
        }
    }

    var logSource: String {
        switch self {
        case .medicalDocumentUpload(let intent):
            return intent.source.rawValue
        case .memberInviteFromPush(let intent):
            return intent.source.rawValue
        case .medicationReminder(let intent):
            return intent.source.rawValue
        case .taskReminder(let intent):
            return intent.source.rawValue
        case .healthResourceChanged(let intent):
            return intent.source.rawValue
        case .appRoute(let intent):
            return intent.source.rawValue
        }
    }
}
