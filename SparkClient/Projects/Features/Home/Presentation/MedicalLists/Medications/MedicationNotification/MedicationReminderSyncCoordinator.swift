import Foundation

struct MedicationReminderMemberSnapshot: Sendable {
    let memberID: Int
    let memberDisplayName: String
    let isSelfMember: Bool
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
    private var cachedPlanDrugNames: [Int: String] = [:]

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
        cachedPlanDrugNames = [:]
        preferencesStore.deactivate()
    }

    /// 通知管理页展示药品名：优先复用最近一次 enabled-plans 结果，避免按成员 N+1 拉计划。
    func planDrugNamesForManagementDisplay() async -> [Int: String] {
        if cachedPlanDrugNames.isEmpty == false {
            return cachedPlanDrugNames
        }
        guard let response = await fetchEnabledPlansResponse(includeRecords: false) else {
            return [:]
        }
        cachedPlanDrugNames = Self.planDrugNames(from: response)
        return cachedPlanDrugNames
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

    func rebuildAfterPlanChanged(
        accountID: Int64,
        members: [Member]
    ) {
        requestRebuild(accountID: accountID, members: members, reason: "plan_changed", immediate: true)
    }

    func requestSystemPermissionAndRebuild(
        accountID: Int64,
        members: [Member]
    ) async {
        _ = await permissionCoordinator.requestAuthorizationIfNeeded()
        await rebuildNow(accountID: accountID, members: members, reason: "permission_granted")
    }

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

        guard let snapshots = await loadSnapshots(accountID: accountID) else {
            logger.info("用药提醒重建跳过：enabled-plans 失败，保留现有通知 reason=\(reason)", module: .push)
            return
        }

        let now = Date()
        let calendar = Calendar.current
        var allEvents: [MedicationReminderEvent] = []

        for snapshot in snapshots {
            let input = MedicationReminderCompileInput(
                accountID: accountID,
                memberID: snapshot.memberID,
                memberDisplayName: snapshot.memberDisplayName,
                isSelfMember: snapshot.isSelfMember,
                plans: snapshot.plans,
                records: snapshot.records,
                now: now,
                windowDays: MedicationReminderNotification.defaultWindowDays,
                calendar: calendar,
                showsDrugNameInNotification: preferencesStore.showsDrugNameInNotification
            )
            let result = MedicationReminderScheduleCompiler.compile(input)
            if result.truncatedCount > 0 {
                logger.warning("用药提醒编译截断 truncated=\(result.truncatedCount) memberID=\(snapshot.memberID)", module: .push)
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

    /// 补全通知直接使用服务端聚合结果；服务端已完成本人/已授权非本人计划过滤。
    private func loadSnapshots(accountID: Int64) async -> [MedicationReminderMemberSnapshot]? {
        guard let response = await fetchEnabledPlansResponse(includeRecords: true) else {
            return nil
        }

        cachedPlanDrugNames = Self.planDrugNames(from: response)
        logger.info(
            "enabled-plans 拉取成功 accountID=\(accountID) members=\(response.members.count)",
            module: .push
        )
        return response.members.map { group in
            MedicationReminderMemberSnapshot(
                memberID: group.member.id,
                memberDisplayName: group.member.name,
                isSelfMember: group.member.isSelfMember,
                plans: group.plans,
                records: group.records
            )
        }
    }

    private func fetchEnabledPlansResponse(
        includeRecords: Bool
    ) async -> SparkMedicalSyncAPI.RemoteMedicationReminderEnabledPlansResponse? {
        let calendar = Calendar.current
        let now = Date()
        let windowStart = calendar.startOfDay(for: now)
        let windowEnd = calendar.date(
            byAdding: .day,
            value: MedicationReminderNotification.defaultWindowDays,
            to: windowStart
        ) ?? now

        do {
            return try await medicalQueryAPI.listMedicationReminderEnabledPlans(
                windowStartDate: windowStart,
                windowEndDate: windowEnd,
                includeRecords: includeRecords
            )
        } catch {
            logger.warning(
                "enabled-plans 拉取失败 error=\(error.localizedDescription)",
                module: .push
            )
            return nil
        }
    }

    private static func planDrugNames(
        from response: SparkMedicalSyncAPI.RemoteMedicationReminderEnabledPlansResponse
    ) -> [Int: String] {
        var names: [Int: String] = [:]
        for group in response.members {
            for plan in group.plans {
                names[plan.id] = plan.drugName
            }
        }
        return names
    }
}
