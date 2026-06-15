import Foundation

struct MedicationReminderMemberSnapshot: Sendable {
    let member: Member
    let plans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    let records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
}

@MainActor
final class MedicationReminderSyncCoordinator {
    private let notificationManager: MedicationReminderNotificationManager
    private let permissionCoordinator: MedicationReminderPermissionCoordinator
    private let preferencesStore: MedicationReminderPreferencesStore
    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let logger: Logger

    private var rebuildTask: Task<Void, Never>?
    private var lastRebuildAt: Date?
    private var lastKnownTimeZone = TimeZone.current.identifier
    private var isRebuilding = false

    var permissionCoordinatorAccess: MedicationReminderPermissionCoordinator {
        permissionCoordinator
    }

    var notificationManagerAccess: MedicationReminderNotificationManager {
        notificationManager
    }

    init(
        notificationManager: MedicationReminderNotificationManager,
        permissionCoordinator: MedicationReminderPermissionCoordinator,
        preferencesStore: MedicationReminderPreferencesStore,
        medicalQueryAPI: SparkMedicalQueryAPI,
        logger: Logger
    ) {
        self.notificationManager = notificationManager
        self.permissionCoordinator = permissionCoordinator
        self.preferencesStore = preferencesStore
        self.medicalQueryAPI = medicalQueryAPI
        self.logger = logger
    }

    func activate(accountID: Int64) {
        preferencesStore.activate(accountID: accountID)
    }

    func deactivate() {
        rebuildTask?.cancel()
        preferencesStore.deactivate()
    }

    func clearAllForAccount(_ accountID: Int64) async {
        rebuildTask?.cancel()
        await notificationManager.removeAllMedicationNotifications(forAccountID: accountID)
    }

    func requestRebuild(
        accountID: Int64,
        members: [Member],
        reason: String,
        immediate: Bool = false
    ) {
        if immediate == false, isRebuilding {
            return
        }
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            guard let self else { return }
            if immediate == false {
                try? await Task.sleep(nanoseconds: UInt64(MedicationReminderNotification.rebuildDebounceSeconds * 1_000_000_000))
            }
            guard Task.isCancelled == false else { return }
            await rebuild(accountID: accountID, members: members, reason: reason)
        }
    }

    func rebuildIfStale(
        accountID: Int64,
        members: [Member],
        reason: String
    ) {
        if TimeZone.current.identifier != lastKnownTimeZone {
            lastKnownTimeZone = TimeZone.current.identifier
            requestRebuild(accountID: accountID, members: members, reason: "timezone_changed", immediate: true)
            return
        }

        if let lastRebuildAt,
           Date().timeIntervalSince(lastRebuildAt) < MedicationReminderNotification.foregroundRebuildThresholdSeconds {
            return
        }
        requestRebuild(accountID: accountID, members: members, reason: reason, immediate: true)
    }

    func handleDoseCompleted(
        accountID: Int64,
        memberID: Int,
        planID: Int,
        scheduledAt: Date,
        doseSequence: Int,
        members: [Member]
    ) async {
        await notificationManager.removeNotifications(
            containing: [MedicationReminderLaunchItem(planID: planID, doseSequence: doseSequence)],
            memberID: memberID,
            accountID: accountID,
            scheduledAt: scheduledAt
        )
        requestRebuild(accountID: accountID, members: members, reason: "dose_completed", immediate: true)
    }

    /// 计划变更后重建通知，不主动弹出系统权限对话框。
    func rebuildAfterPlanChanged(
        accountID: Int64,
        members: [Member]
    ) {
        requestRebuild(accountID: accountID, members: members, reason: "plan_changed", immediate: true)
    }

    /// 用户看完应用内说明并点击「继续」后，再请求系统权限并重建。
    func requestSystemPermissionAndRebuild(
        accountID: Int64,
        members: [Member]
    ) async {
        _ = await permissionCoordinator.requestAuthorizationIfNeeded()
        await rebuildNow(accountID: accountID, members: members, reason: "permission_granted")
    }

    /// 管理页手动补齐：同步等待重建完成后再刷新列表。
    func rebuildNow(
        accountID: Int64,
        members: [Member],
        reason: String = "manual_reschedule"
    ) async {
        rebuildTask?.cancel()
        await rebuild(accountID: accountID, members: members, reason: reason)
    }

    private func rebuild(accountID: Int64, members: [Member], reason: String) async {
        guard isRebuilding == false else {
            logger.debug("用药提醒重建跳过：已有重建进行中 reason=\(reason)", module: .push)
            return
        }
        isRebuilding = true
        defer { isRebuilding = false }

        guard await permissionCoordinator.canScheduleNotifications else {
            logger.info("用药提醒重建跳过：系统通知未授权 reason=\(reason)", module: .push)
            return
        }

        let snapshots = await loadSnapshots(accountID: accountID, members: members)
        let now = Date()
        let calendar = Calendar.current
        var allEvents: [MedicationReminderEvent] = []

        for snapshot in snapshots {
            let input = MedicationReminderCompileInput(
                accountID: accountID,
                memberID: snapshot.member.id,
                memberDisplayName: snapshot.member.name,
                isSelfMember: snapshot.member.relationship == "self",
                plans: snapshot.plans,
                records: snapshot.records,
                now: now,
                windowDays: MedicationReminderNotification.defaultWindowDays,
                calendar: calendar,
                showsDrugNameInNotification: preferencesStore.showsDrugNameInNotification
            )
            let result = MedicationReminderScheduleCompiler.compile(input)
            if result.truncatedCount > 0 {
                logger.warning("用药提醒编译截断 truncated=\(result.truncatedCount) memberID=\(snapshot.member.id)", module: .push)
            }
            allEvents.append(contentsOf: result.events)
        }

        allEvents.sort { $0.scheduledAt < $1.scheduledAt }
        if allEvents.count > MedicationReminderNotification.maxPendingCount {
            let truncated = allEvents.count - MedicationReminderNotification.maxPendingCount
            allEvents = Array(allEvents.prefix(MedicationReminderNotification.maxPendingCount))
            logger.warning("用药提醒全局截断 truncated=\(truncated)", module: .push)
        }

        await notificationManager.rebuild(events: allEvents, accountID: accountID)
        lastRebuildAt = Date()
        logger.info("用药提醒重建完成 reason=\(reason) count=\(allEvents.count)", module: .push)
    }

    private func loadSnapshots(accountID: Int64, members: [Member]) async -> [MedicationReminderMemberSnapshot] {
        var snapshots: [MedicationReminderMemberSnapshot] = []
        let calendar = Calendar.current
        let now = Date()
        let windowStart = calendar.startOfDay(for: now)
        let windowEnd = calendar.date(byAdding: .day, value: MedicationReminderNotification.defaultWindowDays, to: now) ?? now

        for member in members {
            do {
                let plans = try await medicalQueryAPI.listMedicationPlans(memberID: member.id)
                let records = try await medicalQueryAPI.listMedicationRecords(
                    memberID: member.id,
                    scheduledRange: MedicationRecordScheduledRange(
                        scheduledFrom: windowStart,
                        scheduledToExclusive: windowEnd.addingTimeInterval(86_400)
                    )
                )
                snapshots.append(MedicationReminderMemberSnapshot(member: member, plans: plans, records: records))
            } catch {
                logger.warning("用药提醒加载成员数据失败 memberID=\(member.id) error=\(error.localizedDescription)", module: .push)
            }
        }
        return snapshots
    }
}
