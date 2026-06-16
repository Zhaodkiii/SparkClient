import Combine
import SwiftUI

struct NonSelfReminderPrompt: Identifiable {
    let id = UUID()
    let memberID: Int
    let memberName: String
}

/// 用药计划保存后的提醒协同 UI（分享、本机代提醒确认、已通知成员本人等），挂载在计划详情页。
@MainActor
final class MedicationReminderPostSaveController: ObservableObject {
    /// 分享前先询问用户，确认后再打开 ShareSheet
    @Published var shareConfirmMember: Member?
    @Published var pendingShareMember: Member?
    @Published var pendingNonSelfReminderPrompt: NonSelfReminderPrompt?
    @Published var showOwnerNotifiedAlert = false
    @Published var ownerNotifiedApnsAvailable = false
    @Published var showMedicationReminderPermissionExplanation = false

    private static let presentationGapNanoseconds: UInt64 = 400_000_000

    private func afterPresentationGap(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.presentationGapNanoseconds)
            action()
        }
    }

    func handlePlanChanged(
        _ plan: SparkMedicalSyncAPI.RemoteMedicationPlan?,
        homeDependencies: HomeFeatureDependencies,
        memberContextStore: MemberContextStore,
        memberID: Int?,
        notificationClient: any NotificationClient
    ) {
        guard let memberID else { return }
        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }

        let members = memberContextStore.context.members
        let coordinator = homeDependencies.medicationReminderSyncCoordinator
        coordinator.activate(accountID: session.accountID)

        guard plan?.reminderEnabled == true else {
            coordinator.rebuildAfterPlanChanged(accountID: session.accountID, members: members)
            return
        }

        Task {
            let action = await homeDependencies.medicationReminderOwnershipCoordinator.resolvePostSaveAction(
                accountID: session.accountID,
                memberID: memberID,
                reminderEnabled: true
            )
            switch action {
            case .none:
                coordinator.rebuildAfterPlanChanged(accountID: session.accountID, members: members)
            case .requestLocalNotificationForSelf:
                let status = await coordinator.permissionCoordinatorAccess.currentStatus()
                if status == .notDetermined {
                    showMedicationReminderPermissionExplanation = true
                } else {
                    coordinator.rebuildAfterPlanChanged(accountID: session.accountID, members: members)
                }
            case .openShare(let shareMemberID):
                if let member = members.first(where: { $0.id == shareMemberID }) {
                    shareConfirmMember = member
                }
            case .showLocalReminderConfirm(let promptMemberID, let memberName):
                pendingNonSelfReminderPrompt = NonSelfReminderPrompt(memberID: promptMemberID, memberName: memberName)
            case .showOwnerNotified(let apnsAvailable):
                ownerNotifiedApnsAvailable = apnsAvailable
                showOwnerNotifiedAlert = true
            }
        }
    }

    func confirmShare() {
        guard let member = shareConfirmMember else { return }
        shareConfirmMember = nil
        afterPresentationGap {
            self.pendingShareMember = member
        }
    }

    func declineShare() {
        guard let member = shareConfirmMember else { return }
        shareConfirmMember = nil
        afterPresentationGap {
            self.pendingNonSelfReminderPrompt = NonSelfReminderPrompt(
                memberID: member.id,
                memberName: member.name
            )
        }
    }

    func acceptNonSelfLocalReminder(
        homeDependencies: HomeFeatureDependencies,
        memberContextStore: MemberContextStore
    ) {
        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
        guard let prompt = pendingNonSelfReminderPrompt else { return }
        pendingNonSelfReminderPrompt = nil
        Task {
            await homeDependencies.medicationReminderOwnershipCoordinator.acceptLocalReminderForNonSelfMember(
                accountID: session.accountID,
                memberID: prompt.memberID,
                members: memberContextStore.context.members
            )
        }
    }

    func declineNonSelfLocalReminder(homeDependencies: HomeFeatureDependencies) {
        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
        guard let prompt = pendingNonSelfReminderPrompt else { return }
        pendingNonSelfReminderPrompt = nil
        homeDependencies.medicationReminderOwnershipCoordinator.declineLocalReminderForNonSelfMember(
            accountID: session.accountID,
            memberID: prompt.memberID
        )
    }

    func confirmMedicationReminderPermissionRequest(
        homeDependencies: HomeFeatureDependencies,
        memberContextStore: MemberContextStore
    ) {
        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
        Task {
            await homeDependencies.medicationReminderSyncCoordinator.requestSystemPermissionAndRebuild(
                accountID: session.accountID,
                members: memberContextStore.context.members
            )
        }
    }

    func skipMedicationReminderPermissionRequest(
        homeDependencies: HomeFeatureDependencies,
        memberContextStore: MemberContextStore,
        notificationClient: any NotificationClient
    ) {
        guard case .signedIn(let session) = homeDependencies.sessionStore.state else { return }
        notificationClient.info(
            L10n.text("medication_reminder.permission.skipped_toast"),
            title: L10n.text("medication_reminder.title"),
            source: "medication_reminder"
        )
        homeDependencies.medicationReminderSyncCoordinator.rebuildAfterPlanChanged(
            accountID: session.accountID,
            members: memberContextStore.context.members
        )
    }
}

private struct MedicationReminderPostSaveHandlingModifier: ViewModifier {
    @ObservedObject var controller: MedicationReminderPostSaveController
    let homeDependencies: HomeFeatureDependencies
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient

    func body(content: Content) -> some View {
        content
            .medicationReminderPermissionExplanation(
                isPresented: $controller.showMedicationReminderPermissionExplanation,
                onContinue: {
                    controller.confirmMedicationReminderPermissionRequest(
                        homeDependencies: homeDependencies,
                        memberContextStore: memberContextStore
                    )
                },
                onSkip: {
                    controller.skipMedicationReminderPermissionRequest(
                        homeDependencies: homeDependencies,
                        memberContextStore: memberContextStore,
                        notificationClient: notificationClient
                    )
                }
            )
            .alert(
                L10n.text("medication.reminder.share_confirm.title"),
                isPresented: Binding(
                    get: { controller.shareConfirmMember != nil },
                    set: { if $0 == false { controller.shareConfirmMember = nil } }
                )
            ) {
                Button(L10n.text("medication.reminder.share_confirm.decline"), role: .cancel) {
                    controller.declineShare()
                }
                Button(L10n.text("medication.reminder.share_confirm.accept")) {
                    controller.confirmShare()
                }
            } message: {
                Text(L10n.text("medication.reminder.share_confirm.message"))
            }
            .sheet(item: $controller.pendingShareMember) { member in
                ShareSheet(
                    member: member,
                    shareUseCase: homeDependencies.shareMemberUseCase,
                    inviteUseCase: homeDependencies.memberInviteUseCase
                )
            }
            .alert(
                L10n.text("medication.reminder.non_self.confirm.title"),
                isPresented: Binding(
                    get: { controller.pendingNonSelfReminderPrompt != nil },
                    set: { if $0 == false { controller.pendingNonSelfReminderPrompt = nil } }
                )
            ) {
                Button(L10n.text("medication.reminder.non_self.confirm.decline"), role: .cancel) {
                    controller.declineNonSelfLocalReminder(homeDependencies: homeDependencies)
                }
                Button(L10n.text("medication.reminder.non_self.confirm.accept")) {
                    controller.acceptNonSelfLocalReminder(
                        homeDependencies: homeDependencies,
                        memberContextStore: memberContextStore
                    )
                }
            } message: {
                Text(L10n.text("medication.reminder.non_self.confirm.message"))
            }
            .alert(
                controller.ownerNotifiedApnsAvailable
                ? L10n.text("medication.reminder.owner_notified.title")
                : L10n.text("medication.reminder.owner_apns_unavailable.title"),
                isPresented: $controller.showOwnerNotifiedAlert
            ) {
                Button(L10n.text("common.confirm", fallback: "好的")) {}
            } message: {
                Text(
                    controller.ownerNotifiedApnsAvailable
                    ? L10n.text("medication.reminder.owner_notified.message")
                    : L10n.text("medication.reminder.owner_apns_unavailable.message")
                )
            }
    }
}

extension View {
    func medicationReminderPostSaveHandling(
        controller: MedicationReminderPostSaveController,
        homeDependencies: HomeFeatureDependencies?,
        memberContextStore: MemberContextStore,
        notificationClient: any NotificationClient
    ) -> some View {
        Group {
            if let homeDependencies {
                modifier(
                    MedicationReminderPostSaveHandlingModifier(
                        controller: controller,
                        homeDependencies: homeDependencies,
                        memberContextStore: memberContextStore,
                        notificationClient: notificationClient
                    )
                )
            } else {
                self
            }
        }
    }
}
