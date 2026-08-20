import SwiftUI

@MainActor
struct IOS26HomeDashboardActionHandler {
    let routeStore: AppRouteStore
    let homeViewModel: HomeViewModel
    let medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    let chatListViewModel: ChatListViewModel
    let deepTutorChatViewModel: DeepTutorChatViewModel
    let notificationClient: any NotificationClient
    let quickStartPreferenceStore: HomeQuickStartConversationPreferenceStore
    let autoSmallTaskRegistry: AutoSmallTaskRegistry
    let autoSmallTaskIntentStore: ChatAutoSmallTaskIntentStore
    let ownerAccountID: Int64

    func handle(_ action: IOS26HomeActionItem.Kind) {
        switch action {
        case .checkupPlan:
            Task {
                await openAutoSmallTaskInChat(
                    mode: .checkupPlan,
                    definition: BuiltInAutoSmallTaskCatalog.healthExamPlan
                )
            }
        case .reportInterpretation:
            Task { await openQuickStart(mode: .reportInterpretation) }
        case .reportUpload:
            medicalDocumentUploadViewModel.reset()
            medicalDocumentUploadViewModel.presentUploadPage()
        case .medication:
            homeViewModel.logMedicalListNavigation(kind: .medicationPlans)
            routeStore.route(to: .homeMedicalList(.medication, nil))
        case .familyMedicineCabinet:
            guard let memberID = homeViewModel.selectedMemberID else {
                notificationClient.info(
                    L10n.text("ios26.home.family_medicine_cabinet.member_required"),
                    title: L10n.text("ios26.home.action.family_medicine_cabinet.title"),
                    source: "ios26_home"
                )
                return
            }
            routeStore.route(to: .homeFamilyMedicineCabinet(memberID: memberID))
        case .familyArchive:
            homeViewModel.openFamilyArchiveEntry()
        }
    }

    private func openAutoSmallTaskInChat(
        mode: ChatQuickStartMode,
        definition: AutoSmallTaskDefinition
    ) async {
        let source = "ios26_home_\(mode.rawValue)"
        let registration: AutoSmallTaskRegistrationResult
        do {
            registration = try await autoSmallTaskRegistry.registerOrMigrateIfNeeded(
                definition: definition,
                userID: ownerAccountID
            )
        } catch {
            notificationClient.error(
                L10n.text("chat.auto_small_task.init_failed", fallback: "小任务初始化失败，请稍后重试。"),
                title: mode.title,
                source: "ios26_home"
            )
            await openChat(mode: mode)
            return
        }

        guard registration.isRunnable, let smallTask = registration.smallTask else {
            notificationClient.error(
                L10n.text("chat.auto_small_task.init_failed", fallback: "小任务初始化失败，请稍后重试。"),
                title: mode.title,
                source: "ios26_home"
            )
            await openChat(mode: mode)
            return
        }

        guard let threadID = await createChatThread(mode: mode, source: source) else { return }
        autoSmallTaskIntentStore.create(
            threadID: threadID,
            businessKey: definition.businessKey,
            smallTaskCode: smallTask.code,
            localSmallTaskID: smallTask.id,
            source: source,
            initialDraftHash: ChatAutoSmallTaskDraftHasher.hash(mode.initialDraft)
        )
        routeStore.route(to: .chatThread(threadID))
    }

    private func openQuickStart(mode: DeepTutorQuickStartMode) async {
        switch quickStartPreferenceStore.target {
        case .chat:
            switch mode {
            case .checkupPlan:
                await openAutoSmallTaskInChat(
                    mode: .checkupPlan,
                    definition: BuiltInAutoSmallTaskCatalog.healthExamPlan
                )
            case .reportInterpretation:
                await openAutoSmallTaskInChat(
                    mode: .reportInterpretation,
                    definition: BuiltInAutoSmallTaskCatalog.reportInterpretation
                )
            }
        case .deepTutorChat:
            await openDeepTutor(mode: mode)
        }
    }

    private func openChat(mode: ChatQuickStartMode) async {
        guard let threadID = await createChatThread(
            mode: mode,
            source: "ios26_home_\(mode.rawValue)"
        ) else { return }
        routeStore.route(to: .chatThread(threadID))
    }

    private func createChatThread(mode: ChatQuickStartMode, source: String) async -> UUID? {
        guard let threadID = await chatListViewModel.createQuickStartThread(
            mode: mode,
            source: source
        ) else {
            if let error = chatListViewModel.quickStartCreationError {
                notificationClient.error(error, title: mode.title, source: "ios26_home")
            }
            return nil
        }
        return threadID
    }

    private func openDeepTutor(mode: DeepTutorQuickStartMode) async {
        guard let conversationID = await deepTutorChatViewModel.createQuickStartConversation(
            mode: mode,
            source: "ios26_home_\(mode.rawValue)"
        ) else {
            if let error = deepTutorChatViewModel.conversationCreationError {
                notificationClient.error(error, title: mode.title, source: "ios26_home")
            }
            return
        }
        routeStore.route(to: .deepTutorThread(conversationID))
    }
}
