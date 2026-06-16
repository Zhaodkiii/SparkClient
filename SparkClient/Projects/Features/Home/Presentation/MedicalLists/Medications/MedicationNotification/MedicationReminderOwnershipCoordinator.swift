import Foundation

enum MedicationReminderPostSaveAction: Equatable {
    case none
    case requestLocalNotificationForSelf
    case openShare(memberID: Int)
    case showLocalReminderConfirm(memberID: Int, memberName: String)
    case showOwnerNotified(apnsAvailable: Bool)
}

@MainActor
final class MedicationReminderOwnershipCoordinator {
    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let syncCoordinator: MedicationReminderSyncCoordinator
    private let consentStore: MedicationReminderConsentStore
    private let notificationClient: any NotificationClient
    private let logger: Logger

    init(
        medicalQueryAPI: SparkMedicalQueryAPI,
        syncCoordinator: MedicationReminderSyncCoordinator,
        consentStore: MedicationReminderConsentStore,
        notificationClient: any NotificationClient,
        logger: Logger
    ) {
        self.medicalQueryAPI = medicalQueryAPI
        self.syncCoordinator = syncCoordinator
        self.consentStore = consentStore
        self.notificationClient = notificationClient
        self.logger = logger
    }

    /// 保存成功后的引导流程按「本人 / 非本人无本人绑定 / 非本人有本人绑定」三段分流。
    func resolvePostSaveAction(
        accountID: Int64,
        memberID: Int,
        reminderEnabled: Bool
    ) async -> MedicationReminderPostSaveAction {
        guard reminderEnabled else {
            return .none
        }

        do {
            let ownership = try await medicalQueryAPI.fetchMemberNotificationOwnership(memberID: memberID)
            logger.info(
                "用药提醒归属查询成功 memberID=\(memberID) isSelf=\(ownership.isCurrentUserSelfMember) hasOtherSelfOwner=\(ownership.hasOtherSelfOwner)",
                module: .push
            )

            if ownership.isCurrentUserSelfMember {
                return .requestLocalNotificationForSelf
            }

            if ownership.hasOtherSelfOwner {
                let apnsAvailable = ownership.selfOwners.contains { $0.hasApns && $0.notificationsEnabled }
                return .showOwnerNotified(apnsAvailable: apnsAvailable)
            }

            if ownership.canShare {
                return .openShare(memberID: memberID)
            }

            return .showLocalReminderConfirm(memberID: memberID, memberName: ownership.memberName)
        } catch {
            logger.warning(
                "用药提醒归属查询失败 memberID=\(memberID) error=\(error.localizedDescription)",
                module: .push
            )
            notificationClient.info(
                L10n.text("medication.reminder.sync_degraded.toast"),
                title: L10n.text("medication_reminder.title"),
                source: "medication_reminder"
            )
            return .none
        }
    }

    func acceptLocalReminderForNonSelfMember(
        accountID: Int64,
        memberID: Int,
        members: [Member]
    ) async {
        consentStore.setAllowsLocalReminder(true, accountID: accountID, memberID: memberID, source: "non_self_confirm")
        logger.info("用户同意非本人本机提醒 memberID=\(memberID)", module: .push)
        await syncCoordinator.requestSystemPermissionAndRebuild(accountID: accountID, members: members)
        notificationClient.success(
            L10n.text("medication.reminder.local_consent.saved.toast"),
            title: L10n.text("medication_reminder.title"),
            source: "medication_reminder"
        )
    }

    func declineLocalReminderForNonSelfMember(accountID: Int64, memberID: Int) {
        consentStore.setAllowsLocalReminder(false, accountID: accountID, memberID: memberID, source: "non_self_decline")
        logger.info("用户拒绝非本人本机提醒 memberID=\(memberID)", module: .push)
        notificationClient.info(
            L10n.text("medication.reminder.local_consent.skipped.toast"),
            title: L10n.text("medication_reminder.title"),
            source: "medication_reminder"
        )
    }
}
