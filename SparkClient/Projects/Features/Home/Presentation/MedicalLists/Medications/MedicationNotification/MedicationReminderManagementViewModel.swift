import Combine
import Foundation
import SwiftUI

@MainActor
final class MedicationReminderManagementViewModel: ObservableObject {
    @Published private(set) var groups: [MedicationReminderDisplayGroup] = []
    @Published private(set) var pendingCount = 0
    @Published private(set) var deliveredCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var permissionStatus: MedicationReminderPermissionStatus = .notDetermined
    @Published private(set) var showsDrugNameInNotification = false
    @Published var showPermissionExplanation = false
    @Published var showClearAllConfirmation = false
    @Published var pendingCancelGroup: MedicationReminderDisplayGroup?

    private let accountID: Int64
    private let syncCoordinator: MedicationReminderSyncCoordinator
    private let preferencesStore: MedicationReminderPreferencesStore
    private let memberContextStore: MemberContextStore
    private let notificationClient: any NotificationClient
    private let logger: Logger

    private var notificationManager: MedicationReminderNotificationManager {
        syncCoordinator.notificationManagerAccess
    }

    private var permissionCoordinator: MedicationReminderPermissionCoordinator {
        syncCoordinator.permissionCoordinatorAccess
    }

    init(
        accountID: Int64,
        syncCoordinator: MedicationReminderSyncCoordinator,
        preferencesStore: MedicationReminderPreferencesStore,
        memberContextStore: MemberContextStore,
        notificationClient: any NotificationClient,
        logger: Logger
    ) {
        self.accountID = accountID
        self.syncCoordinator = syncCoordinator
        self.preferencesStore = preferencesStore
        self.memberContextStore = memberContextStore
        self.notificationClient = notificationClient
        self.logger = logger
    }

    var members: [Member] {
        memberContextStore.context.members
    }

    var isPermissionDenied: Bool {
        permissionStatus == .denied
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        syncCoordinator.activate(accountID: accountID)
        permissionStatus = await permissionCoordinator.currentStatus()
        showsDrugNameInNotification = preferencesStore.showsDrugNameInNotification

        let records = await notificationManager.fetchMedicationNotifications(forAccountID: accountID)
        let planDrugNames = await loadPlanDrugNames()
        let memberNames = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.name) })

        groups = records.map { record in
            buildDisplayGroup(from: record, planDrugNames: planDrugNames, memberNames: memberNames)
        }

        pendingCount = records.filter {
            $0.status == .pending || $0.status == .expired
        }.count
        deliveredCount = records.filter { $0.status == .delivered }.count
    }

    func rescheduleNotifications() async {
        permissionStatus = await permissionCoordinator.currentStatus()
        switch permissionStatus {
        case .notDetermined:
            showPermissionExplanation = true
            return
        case .denied:
            notificationClient.info(
                L10n.text("medication_reminder.management.permission_denied_toast"),
                title: L10n.text("medication_reminder.title"),
                source: "medication_reminder"
            )
            return
        case .authorized, .provisional, .ephemeral:
            break
        }

        await syncCoordinator.rebuildNow(accountID: accountID, members: members, reason: "manual_reschedule")
        await load()
        if await permissionCoordinator.canScheduleNotifications {
            notificationClient.success(
                L10n.text("medication_reminder.management.reschedule_success"),
                title: L10n.text("medication_reminder.title"),
                source: "medication_reminder"
            )
        }
    }

    func skipPermissionExplanation() {
        showPermissionExplanation = false
        notificationClient.info(
            L10n.text("medication_reminder.permission.skipped_toast"),
            title: L10n.text("medication_reminder.title"),
            source: "medication_reminder"
        )
        syncCoordinator.rebuildAfterPlanChanged(accountID: accountID, members: members)
    }

    func confirmPermissionExplanationAndReschedule() async {
        showPermissionExplanation = false
        await syncCoordinator.requestSystemPermissionAndRebuild(accountID: accountID, members: members)
        permissionStatus = await permissionCoordinator.currentStatus()
        await load()
        if await permissionCoordinator.canScheduleNotifications {
            notificationClient.success(
                L10n.text("medication_reminder.management.reschedule_success"),
                title: L10n.text("medication_reminder.title"),
                source: "medication_reminder"
            )
        } else {
            notificationClient.info(
                L10n.text("medication_reminder.management.permission_denied_toast"),
                title: L10n.text("medication_reminder.title"),
                source: "medication_reminder"
            )
        }
    }

    func openSystemSettings() {
        permissionCoordinator.openSystemSettings()
    }

    func cancelNotification(_ group: MedicationReminderDisplayGroup) async {
        await notificationManager.removeNotification(id: group.notificationID)
        await load()
        notificationClient.success(
            L10n.text("medication_reminder.management.cancel_success"),
            title: L10n.text("medication_reminder.title"),
            source: "medication_reminder"
        )
    }

    func clearAllNotifications() async {
        await notificationManager.removeAllMedicationNotifications(forAccountID: accountID)
        await load()
        notificationClient.success(
            L10n.text("medication_reminder.management.clear_all_success"),
            title: L10n.text("medication_reminder.title"),
            source: "medication_reminder"
        )
    }

    private func loadPlanDrugNames() async -> [Int: String] {
        await syncCoordinator.planDrugNamesForManagementDisplay()
    }

    private func buildDisplayGroup(
        from record: MedicationReminderNotificationRecord,
        planDrugNames: [Int: String],
        memberNames: [Int: String]
    ) -> MedicationReminderDisplayGroup {
        let displayStatus: MedicationReminderDisplayStatus
        switch record.status {
        case .pending:
            displayStatus = .pending
        case .delivered:
            displayStatus = .delivered
        case .expired:
            displayStatus = .expired
        case .invalid:
            displayStatus = .invalid
        }

        let memberID = record.payload?.memberID
        let memberName: String
        if let memberID, let name = memberNames[memberID] {
            memberName = name
        } else if let memberID {
            memberName = String(
                format: L10n.text("medication_reminder.management.member_fallback", fallback: "成员 #%d"),
                locale: .current,
                memberID
            )
        } else {
            memberName = L10n.text("medication_reminder.management.unknown_member", fallback: "未知成员")
        }

        let items: [MedicationReminderDisplayItem]
        if let payload = record.payload {
            items = payload.items.map { item in
                MedicationReminderDisplayItem(
                    id: "\(item.planID):\(item.doseSequence)",
                    planID: item.planID,
                    doseSequence: item.doseSequence,
                    drugName: planDrugNames[item.planID]
                )
            }
        } else {
            items = []
        }

        return MedicationReminderDisplayGroup(
            id: record.notificationID,
            notificationID: record.notificationID,
            memberID: memberID,
            memberName: memberName,
            scheduledAt: record.scheduledAt,
            status: displayStatus,
            items: items,
            rawBody: record.body
        )
    }
}
