import Foundation

@MainActor
final class HomeLaunchIntentConsumer: LaunchIntentHandling {
    private let coordinator: LaunchIntentCoordinator
    private let routeStore: AppRouteStore
    private let uploadViewModel: MedicalDocumentUploadViewModel
    private let homeViewModel: HomeViewModel
    private let sessionStore: AppSessionStore
    private let logger: Logger

    init(
        coordinator: LaunchIntentCoordinator,
        routeStore: AppRouteStore,
        uploadViewModel: MedicalDocumentUploadViewModel,
        homeViewModel: HomeViewModel,
        sessionStore: AppSessionStore,
        logger: Logger
    ) {
        self.coordinator = coordinator
        self.routeStore = routeStore
        self.uploadViewModel = uploadViewModel
        self.homeViewModel = homeViewModel
        self.sessionStore = sessionStore
        self.logger = logger
    }

    func setHomeHostReady(_ ready: Bool) {
        coordinator.updateReadiness { $0.homeHostReady = ready }
    }

    func syncHostState(
        activeSheet: HomeSheet?,
        activeFullScreenCover: HomeFullScreenCover?,
        isUploadPresented: Bool,
        uploadStage: MedicalDocumentUploadViewModel.Stage
    ) {
        coordinator.updateHostState { state in
            state.activeSheetKind = HomeSheetKind(sheet: activeSheet)
            state.activeFullScreenCoverKind = HomeFullScreenCoverKind(cover: activeFullScreenCover)
            state.isUploadProcessing = isUploadPresented && uploadStage != .picking
        }
    }

    func requestDrain(
        reason: String,
        setActiveFullScreenCover: @escaping (HomeFullScreenCover?) -> Void
    ) {
        coordinator.requestDrain(
            reason: reason,
            handler: self,
            setActiveFullScreenCover: setActiveFullScreenCover
        )
    }

    func availability(for intent: LaunchIntent, hostState: LaunchIntentHostState) -> LaunchIntentAvailability {
        switch intent {
        case .medicalDocumentUpload:
            if hostState.isUploadProcessing {
                return .blocked(.uploadProcessing)
            }
            if hostState.canPresentMedicalUpload == false {
                return .blocked(.fullScreenCoverBusy)
            }
            return .available

        case .memberInviteFromPush:
            if hostState.canPresentMemberInvite {
                return .available
            }
            return .blocked(.homeSheetBusy)

        case .medicationReminder:
            if hostState.activeSheetKind != nil {
                return .blocked(.homeSheetBusy)
            }
            if hostState.activeFullScreenCoverKind != nil && hostState.canPresentMedicalUpload == false {
                return .blocked(.fullScreenCoverBusy)
            }
            return .available

        case .appRoute:
            return .blocked(.unsupportedInPhase)
        }
    }

    func handle(
        _ intent: LaunchIntent,
        setActiveFullScreenCover: @escaping (HomeFullScreenCover?) -> Void
    ) async -> LaunchIntentConsumeResult {
        routeStore.route(to: .home, replaceStack: false)

        switch intent {
        case .medicalDocumentUpload(let uploadIntent):
            do {
                try await consumeMedicalDocumentUpload(
                    uploadIntent,
                    setActiveFullScreenCover: setActiveFullScreenCover
                )
                return .consumed
            } catch {
                return .failedRecoverable(.uploadProcessing)
            }

        case .memberInviteFromPush(let inviteIntent):
            do {
                try await consumeMemberInviteFromPush(inviteIntent)
                return .consumed
            } catch {
                return .failedRecoverable(.homeSheetBusy)
            }

        case .medicationReminder(let reminderIntent):
            return await consumeMedicationReminder(reminderIntent)

        case .appRoute:
            return .failedTerminal(.unsupportedInPhase)
        }
    }

    private func consumeMedicalDocumentUpload(
        _ intent: ExternalMedicalDocumentUploadIntent,
        setActiveFullScreenCover: @escaping (HomeFullScreenCover?) -> Void
    ) async throws {
        uploadViewModel.prepareForExternalImport(files: intent.files)
        setActiveFullScreenCover(.medicalDocumentUpload)
        logger.info(
            "外部 PDF 已进入医疗文档上传页 documentID=\(intent.id)",
            module: .medical
        )

        await Task.yield()
        setActiveFullScreenCover(.medicalDocumentUpload)
        logger.info(
            "外部 PDF 上传弹层已置位 cover=medicalDocumentUpload documentID=\(intent.id)",
            module: .medical
        )
    }

    private func consumeMemberInviteFromPush(_ intent: MemberInvitePushLaunchIntent) async throws {
        logger.info(
            "Push.memberInvite.interaction inviteID=\(intent.inviteID) notificationRequestID=\(intent.notificationRequestID ?? "nil")",
            module: .push
        )
        await homeViewModel.openPendingInvitesFromPush(inviteID: intent.inviteID)
    }

    private func consumeMedicationReminder(_ intent: MedicationReminderLaunchIntent) async -> LaunchIntentConsumeResult {
        guard case .signedIn(let session) = sessionStore.state else {
            return .failedTerminal(.signedOut)
        }

        let payload = intent.payload
        guard payload.accountID == session.accountID else {
            homeViewModel.notifyMedicationReminderUnavailable(
                L10n.text("medication_reminder.route.other_account")
            )
            return .failedTerminal(.accountNotPrepared)
        }

        switch await homeViewModel.waitForMemberAvailability(payload.memberID) {
        case .loading:
            return .notReady
        case .unavailable:
            homeViewModel.notifyMedicationReminderUnavailable(
                L10n.text("medication_reminder.route.member_unavailable")
            )
            return .failedTerminal(.unsupportedInPhase)
        case .available:
            break
        }

        logger.info(
            "MedicationReminder.interaction memberID=\(payload.memberID) notificationID=\(payload.notificationID)",
            module: .push
        )

        await homeViewModel.switchMemberAndLoad(payload.memberID)

        guard homeViewModel.dashboard?.medical.completeData != nil else {
            return .notReady
        }

        let focus = MedicationExecutionInitialFocus(
            scheduledAt: payload.scheduledAt,
            items: payload.items,
            shouldOpenLogSheet: true
        )
        routeStore.route(to: .homeMedicalList(.medicationPlans, focus))
        return .consumed
    }
}
