import Foundation

enum MedicationReminderPostSaveAction: Equatable {
    case none
    case requestLocalNotificationForSelf(planID: Int)
    case requestLocalNotificationForAuthorizedPlan(planID: Int)
    case openShare(memberID: Int, planID: Int)
    case showLocalReminderConfirm(memberID: Int, planID: Int, memberName: String)
    case showOwnerNotified(planID: Int, apnsAvailable: Bool)
}

@MainActor
final class MedicationReminderOwnershipCoordinator {
    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let syncCoordinator: MedicationReminderSyncCoordinator
    private let notificationClient: any NotificationClient
    private let logger: Logger

    init(
        medicalQueryAPI: SparkMedicalQueryAPI,
        syncCoordinator: MedicationReminderSyncCoordinator,
        notificationClient: any NotificationClient,
        logger: Logger
    ) {
        self.medicalQueryAPI = medicalQueryAPI
        self.syncCoordinator = syncCoordinator
        self.notificationClient = notificationClient
        self.logger = logger
    }

    /// 保存成功后的引导流程按「本人 / 非本人无本人绑定 / 非本人有本人绑定」三段分流。
    func resolvePostSaveAction(
        accountID: Int64,
        memberID: Int,
        planID: Int,
        reminderEnabled: Bool
    ) async -> MedicationReminderPostSaveAction {
        guard reminderEnabled else {
            return .none
        }

        do {
            let ownership = try await medicalQueryAPI.fetchMemberNotificationOwnership(memberID: memberID)
            logger.info(
                "用药提醒归属查询成功 accountID=\(accountID) memberID=\(memberID) planID=\(planID) isSelf=\(ownership.isCurrentUserSelfMember) hasOtherSelfOwner=\(ownership.hasOtherSelfOwner)",
                module: .push
            )

            if ownership.isCurrentUserSelfMember {
                return .requestLocalNotificationForSelf(planID: planID)
            }

            if ownership.hasOtherSelfOwner {
                let apnsAvailable = ownership.selfOwners.contains { $0.hasApns && $0.notificationsEnabled }
                return .showOwnerNotified(planID: planID, apnsAvailable: apnsAvailable)
            }

            let authorization = try await medicalQueryAPI.fetchMedicationReminderLocalAuthorization(planID: planID)
            if authorization.enabled {
                return .requestLocalNotificationForAuthorizedPlan(planID: planID)
            }

            if ownership.canShare {
                return .openShare(memberID: memberID, planID: planID)
            }

            return .showLocalReminderConfirm(memberID: memberID, planID: planID, memberName: ownership.memberName)
        } catch {
            logger.warning(
                "用药提醒归属查询失败 memberID=\(memberID) planID=\(planID) error=\(error.localizedDescription)",
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
        planID: Int,
        members: [Member]
    ) async {
        do {
            _ = try await medicalQueryAPI.upsertMedicationReminderLocalAuthorization(
                planID: planID,
                enabled: true,
                source: "share_cancel_confirm"
            )
            logger.info("用户同意非本人本机提醒 memberID=\(memberID) planID=\(planID)", module: .push)
            await syncCoordinator.requestSystemPermissionAndRebuild(accountID: accountID, members: members)
            notificationClient.success(
                L10n.text("medication.reminder.local_authorization.saved.toast"),
                title: L10n.text("medication_reminder.title"),
                source: "medication_reminder"
            )
        } catch {
            logger.warning(
                "保存计划级本机提醒授权失败 memberID=\(memberID) planID=\(planID) error=\(error.localizedDescription)",
                module: .push
            )
            notificationClient.info(
                L10n.text("medication.reminder.sync_degraded.toast"),
                title: L10n.text("medication_reminder.title"),
                source: "medication_reminder"
            )
        }
    }

    func declineLocalReminderForNonSelfMember(accountID: Int64, memberID: Int, planID: Int) {
        logger.info("用户拒绝非本人本机提醒 accountID=\(accountID) memberID=\(memberID) planID=\(planID)", module: .push)
        notificationClient.info(
            L10n.text("medication.reminder.local_authorization.skipped.toast"),
            title: L10n.text("medication_reminder.title"),
            source: "medication_reminder"
        )
    }
}
