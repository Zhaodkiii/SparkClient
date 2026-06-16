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
    @Published var activeSheet: HomeSheet?
    @Published private(set) var pendingInviteCount: Int = 0
    @Published var highlightInviteID: Int?
    @Published private(set) var pendingInvites: [SparkMedicalMemberAPI.PendingInviteItem] = []

    // MARK: Dependencies

    let shareMemberUseCase: ShareMemberUseCase
    let memberInviteUseCase: MemberInviteUseCase
    let manageMemberBindingUseCase: ManageMemberBindingUseCase

    private let sessionStore: AppSessionStore
    private let loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase
    private let memberContextStore: MemberContextStore
    private let notificationClient: any NotificationClient
    private let logger: Logger

    private let logModule = LogModule.home
    private var isInitialLoadInFlight = false
    private var cancellables: Set<AnyCancellable> = []

    var memberContextStoreForBinding: MemberContextStore {
        memberContextStore
    }

    init(
        sessionStore: AppSessionStore,
        loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase,
        memberContextStore: MemberContextStore,
        shareMemberUseCase: ShareMemberUseCase,
        memberInviteUseCase: MemberInviteUseCase,
        manageMemberBindingUseCase: ManageMemberBindingUseCase,
        notificationClient: any NotificationClient,
        logger: Logger
    ) {
        self.sessionStore = sessionStore
        self.loadHomeMedicalOverviewUseCase = loadHomeMedicalOverviewUseCase
        self.memberContextStore = memberContextStore
        self.shareMemberUseCase = shareMemberUseCase
        self.memberInviteUseCase = memberInviteUseCase
        self.manageMemberBindingUseCase = manageMemberBindingUseCase
        self.notificationClient = notificationClient
        self.logger = logger
        memberContextStore.membersDidChange
            .sink { [weak self] in
                guard let self else { return }
                Task {
                    await self.load(syncRemote: true)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .memberInvitePendingRefresh)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.fetchPendingInvitesIfNeeded() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Loading

    /// 首屏加载防重入：用于 Coordinator 预加载与页面 `task` 并发场景。
    func loadInitialIfNeeded(syncRemote: Bool = true) async {
        guard dashboard == nil else { return }
        guard isInitialLoadInFlight == false else { return }

        isInitialLoadInFlight = true
        defer { isInitialLoadInFlight = false }
        await load(syncRemote: syncRemote)
        await fetchPendingInvitesIfNeeded()
    }

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
                session: session,
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

        var medical = medicalResult.medical
        // 保留按需加载的家庭药箱缓存；服务端 complete-data 不返回 familyMedicineBoxes。
        if var completeData = medical.completeData,
           let previousComplete = dashboard?.medical.completeData,
           previousComplete.memberId == completeData.memberId,
           let familyBoxes = previousComplete.familyMedicineBoxes {
            completeData.familyMedicineBoxes = familyBoxes
            medical.completeData = completeData
        }

        let loaded = HomeDashboard(
            session: session,
            members: medicalResult.members,
            selectedMemberID: medicalResult.selectedMemberID,
            medical: medical
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
        await fetchPendingInvitesIfNeeded()
    }

    func refresh() async {
        await load(syncRemote: true)
    }

    func fetchPendingInvitesIfNeeded() async {
        guard case .signedIn = sessionStore.state else {
            pendingInviteCount = 0
            pendingInvites = []
            return
        }
        do {
            let items = try await memberInviteUseCase.fetchPending()
            pendingInvites = items
            pendingInviteCount = items.count
        } catch {
            pendingInviteCount = 0
            pendingInvites = []
        }
    }

    func openInviteAccept(_ item: SparkMedicalMemberAPI.PendingInviteItem) {
        activeSheet = .addMember(.acceptInvite(inviteID: item.inviteId, preview: item))
    }

    func rejectPendingInvite(_ item: SparkMedicalMemberAPI.PendingInviteItem) async {
        do {
            try await memberInviteUseCase.reject(inviteID: item.inviteId)
            await fetchPendingInvitesIfNeeded()
        } catch {
            notificationClient.error(L10n.text("common.error"), title: L10n.text("common.error"), source: "home.invite.reject")
        }
    }

    func consumePendingShareTicketIfNeeded() {
        guard activeSheet == nil else { return }
        guard case .signedIn(let session) = sessionStore.state else { return }
        guard let ticket = PendingMemberShareTicketStore.consume(forAccountID: session.accountID) else { return }
        openAddMemberForShareBinding(ticket: ticket)
    }

    func consumePendingInviteIfNeeded() {
        guard case .signedIn(let session) = sessionStore.state else { return }
        guard let inviteID = PendingMemberInviteStore.consume(forAccountID: session.accountID) else { return }
        Task {
            await fetchPendingInvitesIfNeeded()
            highlightInviteID = inviteID
            activeSheet = .pendingInvites
        }
    }

    func openPendingInvitesFromPush(inviteID: Int) async {
        logger.info("PendingInvites.openFromPush inviteID=\(inviteID)", module: logModule)
        await fetchPendingInvitesIfNeeded()
        let found = pendingInvites.contains { $0.inviteId == inviteID }
        logger.info("PendingInvites.highlight inviteID=\(inviteID) found=\(found)", module: logModule)
        highlightInviteID = inviteID
        activeSheet = .pendingInvites
    }

    func openInviteByID(_ inviteID: Int) async {
        // Fast path: item already in pending list cache.
        if let item = pendingInvites.first(where: { $0.inviteId == inviteID }) {
            openInviteAccept(item)
            return
        }
        // Slow path: fetch detail from API.
        do {
            let item = try await memberInviteUseCase.fetchDetail(inviteID: inviteID)
            openInviteAccept(item)
        } catch {
            logger.warning("openInviteByID fetch failed inviteID=\(inviteID): \(error)", module: logModule)
        }
    }

    func openShareTicket(_ raw: String) {
        guard let ticket = Self.parseShareTicket(from: raw) else { return }
        openAddMemberForShareBinding(ticket: ticket)
    }

    /// 附近设备 / 深链收到票据后，打开新增成员页并由页内解析、进入绑定模式。
    func openAddMemberForShareBinding(ticket: String) {
        activeSheet = .addMember(.create(pendingShareTicket: ticket))
    }

    private static func parseShareTicket(from raw: String) -> String? {
        MemberShareDeepLinkParser.ticket(fromRaw: raw)
    }

    // MARK: - Member selection

    func selectMember(_ memberID: Int?) {
        selectedMemberID = memberID
        memberContextStore.select(memberID: memberID)
        Task { await load(syncRemote: false) }
    }

    func switchMemberAndLoad(_ memberID: Int) async {
        selectedMemberID = memberID
        memberContextStore.select(memberID: memberID)
        await load(syncRemote: true)
    }

    func memberLookupResult(for memberID: Int) -> MedicationReminderMemberLookupResult {
        let members = dashboard?.members ?? memberContextStore.context.members
        if members.contains(where: { $0.id == memberID }) {
            return .available
        }
        if isLoadingMedical || dashboard == nil {
            return .loading
        }
        return .unavailable
    }

    func waitForMemberAvailability(_ memberID: Int, timeoutSeconds: TimeInterval = 12) async -> MedicationReminderMemberLookupResult {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            switch memberLookupResult(for: memberID) {
            case .available, .unavailable:
                return memberLookupResult(for: memberID)
            case .loading:
                if dashboard == nil {
                    await loadInitialIfNeeded(syncRemote: true)
                } else if isLoadingMedical == false {
                    await load(syncRemote: true)
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        return memberLookupResult(for: memberID)
    }

    func memberExists(_ memberID: Int) -> Bool {
        memberLookupResult(for: memberID) == .available
    }

    func notifyMedicationReminderUnavailable(_ message: String) {
        notificationClient.warning(
            message,
            title: L10n.text("medication_reminder.title"),
            source: "medication_reminder"
        )
    }

    func notifyHealthResourceChangedRouteMissing() {
        notificationClient.info(
            L10n.text("notification.health_resource_changed.route_missing.toast"),
            title: L10n.text("notification.health_resource_changed.medication_plan.title"),
            source: "push"
        )
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

    func deleteMember(_ member: Member) async {
        let didDelete = await memberContextStore.deleteMember(member)
        guard didDelete else {
            notificationClient.error(
                L10n.text("common.error"),
                title: L10n.text("common.error"),
                source: "home.member.delete"
            )
            return
        }
        if selectedMemberID == member.id {
            selectedMemberID = nil
            memberContextStore.select(memberID: nil)
        }
        await load(syncRemote: true)
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
