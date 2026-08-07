import SwiftUI

@MainActor
struct IOS26HomeDashboardActionHandler {
    let routeStore: AppRouteStore
    let homeViewModel: HomeViewModel
    let deepTutorChatViewModel: DeepTutorChatViewModel
    let notificationClient: any NotificationClient

    func handle(_ action: IOS26HomeActionItem.Kind) {
        switch action {
        case .checkupPlan:
            Task { await openDeepTutor(mode: .checkupPlan) }
        case .reportInterpretation:
            Task { await openDeepTutor(mode: .reportInterpretation) }
        case .medication:
            homeViewModel.logMedicalListNavigation(kind: .medicationPlans)
            routeStore.route(to: .homeMedicalList(.medicationPlans, nil))
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
