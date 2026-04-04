import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var dashboard: HomeDashboard?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var selectedMemberID: UUID?

    private let sessionStore: AppSessionStore
    private let loadHomeDashboardUseCase: LoadHomeDashboardUseCase
    private let manageHomeMemberUseCase: ManageHomeMemberUseCase
    private let requestHomeHealthAuthorizationUseCase: RequestHomeHealthAuthorizationUseCase
    private let patientContextStore: PatientContextStore
    private let notificationClient: any NotificationClient

    init(
        sessionStore: AppSessionStore,
        loadHomeDashboardUseCase: LoadHomeDashboardUseCase,
        manageHomeMemberUseCase: ManageHomeMemberUseCase,
        requestHomeHealthAuthorizationUseCase: RequestHomeHealthAuthorizationUseCase,
        patientContextStore: PatientContextStore,
        notificationClient: any NotificationClient
    ) {
        self.sessionStore = sessionStore
        self.loadHomeDashboardUseCase = loadHomeDashboardUseCase
        self.manageHomeMemberUseCase = manageHomeMemberUseCase
        self.requestHomeHealthAuthorizationUseCase = requestHomeHealthAuthorizationUseCase
        self.patientContextStore = patientContextStore
        self.notificationClient = notificationClient
    }

    func load() async {
        guard case .signedIn(let session) = sessionStore.state else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await loadHomeDashboardUseCase.execute(
                profileID: session.profileID,
                selectedMemberID: selectedMemberID
            )
            dashboard = loaded
            selectedMemberID = loaded.selectedMember?.id
            patientContextStore.update(members: loaded.members, selectedMemberID: loaded.selectedMemberID)
            errorMessage = nil
        } catch {
            errorMessage = nil
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.dashboard")
        }
    }

    func refresh() async {
        await load()
    }

    func selectMember(_ memberID: UUID?) {
        selectedMemberID = memberID
        patientContextStore.select(memberID: memberID)
        Task { await refresh() }
    }

    func requestHealthAuthorization() async {
        do {
            _ = try await requestHomeHealthAuthorizationUseCase.execute()
            await refresh()
        } catch {
            errorMessage = nil
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.healthAuth")
        }
    }

    func addMember(
        name: String,
        relationship: String,
        age: Int,
        gender: String,
        birthDate: Date?
    ) async {
        do {
            try await manageHomeMemberUseCase.create(
                name: name,
                relationship: relationship,
                age: age,
                gender: gender,
                birthDate: birthDate
            )
            await refresh()
        } catch {
            errorMessage = nil
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.member.create")
        }
    }

    func updateMember(
        _ member: Member,
        name: String,
        relationship: String,
        age: Int,
        gender: String,
        birthDate: Date?
    ) async {
        do {
            try await manageHomeMemberUseCase.update(
                member: member,
                name: name,
                relationship: relationship,
                age: age,
                gender: gender,
                birthDate: birthDate
            )
            await refresh()
        } catch {
            errorMessage = nil
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.member.update")
        }
    }

    func deleteMember(_ member: Member) async {
        do {
            try await manageHomeMemberUseCase.delete(member: member)
            if selectedMemberID == member.id {
                selectedMemberID = nil
                patientContextStore.select(memberID: nil)
            }
            await refresh()
        } catch {
            errorMessage = nil
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.member.delete")
        }
    }

#if DEBUG
    func injectPreviewDashboard(_ dashboard: HomeDashboard) {
        self.dashboard = dashboard
        self.errorMessage = nil
        self.isLoading = false
        self.selectedMemberID = dashboard.selectedMember?.id
    }
#endif
}
