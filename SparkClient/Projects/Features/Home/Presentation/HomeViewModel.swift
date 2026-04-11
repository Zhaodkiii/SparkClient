import Combine
import Foundation

/// 首页状态：协调「医疗摘要」（按成员、服务端快照）。
@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: Published state

    @Published private(set) var dashboard: HomeDashboard?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMedical = false
    @Published private(set) var errorMessage: String?
    @Published var selectedMemberID: Int?

    // MARK: Dependencies

    private let sessionStore: AppSessionStore
    private let loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase
    private let manageHomeMemberUseCase: ManageHomeMemberUseCase
    private let memberContextStore: MemberContextStore
    private let notificationClient: any NotificationClient
    private let logger: Logger

    private let logModule = LogModule.home

    init(
        sessionStore: AppSessionStore,
        loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase,
        manageHomeMemberUseCase: ManageHomeMemberUseCase,
        memberContextStore: MemberContextStore,
        notificationClient: any NotificationClient,
        logger: Logger
    ) {
        self.sessionStore = sessionStore
        self.loadHomeMedicalOverviewUseCase = loadHomeMedicalOverviewUseCase
        self.manageHomeMemberUseCase = manageHomeMemberUseCase
        self.memberContextStore = memberContextStore
        self.notificationClient = notificationClient
        self.logger = logger
    }

    // MARK: - Loading

    func load(syncRemote: Bool = true) async {
        guard case .signedIn(let session) = sessionStore.state else { return }

        isLoading = true
        defer { isLoading = false }

        let startedAt = Date()
        logger.info(
            "首页加载开始 syncRemote=\(syncRemote) selectedMemberID=\(selectedMemberID.map(String.init) ?? "nil")",
            module: logModule
        )

        isLoadingMedical = true
        let medicalResult: HomeMedicalLoadResult
        do {
            medicalResult = try await loadHomeMedicalOverviewUseCase.execute(
                profileID: session.profileID,
                selectedMemberID: selectedMemberID,
                refreshRemoteSnapshot: syncRemote
            )
        } catch {
            isLoadingMedical = false
            errorMessage = nil
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.dashboard")
            logger.warning("首页医疗摘要失败: \(error.localizedDescription)", module: logModule)
            return
        }
        isLoadingMedical = false

        let loaded = HomeDashboard(
            profile: medicalResult.profile,
            members: medicalResult.members,
            selectedMemberID: medicalResult.selectedMemberID,
            medical: medicalResult.medical
        )
        dashboard = loaded
        selectedMemberID = loaded.selectedMember?.id
        memberContextStore.update(members: loaded.members, selectedMemberID: loaded.selectedMemberID)
        errorMessage = nil

        let cost = Date().timeIntervalSince(startedAt)
        logger.info(
            "首页加载完成 cost=\(String(format: "%.3f", cost))s syncRemote=\(syncRemote)",
            module: logModule
        )
    }

    func refresh() async {
        await load(syncRemote: true)
    }

    // MARK: - Member selection

    func selectMember(_ memberID: Int?) {
        selectedMemberID = memberID
        memberContextStore.select(memberID: memberID)
        Task { await load(syncRemote: false) }
    }

    /// 记录首页医疗卡片跳转行为，便于后续分析用户使用路径。
    func logMedicalListNavigation(kind: HomeDashboard.MedicalCard.Kind) {
        logger.info(
            "首页医疗卡片跳转 kind=\(kind) selectedMemberID=\(selectedMemberID.map(String.init) ?? "nil")",
            module: logModule
        )
    }

    /// 列表页按需懒加载明细后，回写首页持有的 `completeData`，避免再次进入列表重复请求。
    func updateMedicalCompleteData(
        _ transform: (inout SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void
    ) {
        guard var dashboard else { return }
        guard var completeData = dashboard.medical.completeData else { return }

        transform(&completeData)
        dashboard.medical.completeData = completeData
        self.dashboard = dashboard
    }

    // MARK: - Member CRUD

    func addMember(
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async {
        do {
            try await manageHomeMemberUseCase.create(
                name: name,
                relationship: relationship,
                gender: gender,
                birthDate: birthDate
            )
            await load(syncRemote: true)
        } catch {
            errorMessage = nil
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.member.create")
        }
    }

    func updateMember(
        _ member: Member,
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async {
        do {
            try await manageHomeMemberUseCase.update(
                member: member,
                name: name,
                relationship: relationship,
                gender: gender,
                birthDate: birthDate
            )
            await load(syncRemote: true)
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
                memberContextStore.select(memberID: nil)
            }
            await load(syncRemote: true)
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
        self.isLoadingMedical = false
        self.selectedMemberID = dashboard.selectedMember?.id
    }
#endif
}
