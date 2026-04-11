import Combine
import Foundation

/// 首页状态：协调「医疗摘要」（本地/同步快照、按成员）与「运动健康」（仅本人 HealthKit），二者加载阶段与失败域相互独立。
@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: Published state

    /// 当前聚合后的首页数据；医疗与运动健康分别来自 `HomeMedicalOverview` / `HomeMotionHealthOverview`。
    @Published private(set) var dashboard: HomeDashboard?
    /// 整页加载中（医疗或运动任一进行中即为 `true`）。
    @Published private(set) var isLoading = false
    /// 医疗摘要（档案 + 快照 + 卡片）加载中。
    @Published private(set) var isLoadingMedical = false
    /// 运动健康（HealthKit）加载中。
    @Published private(set) var isLoadingMotion = false
    /// 预留：业务层若需展示内联错误文案可使用；当前错误主要通过 `notificationClient` 提示。
    @Published private(set) var errorMessage: String?
    /// 用户选中的成员；`nil` 时由用例回退为列表首位。
    @Published var selectedMemberID: Int?

    // MARK: Dependencies

    private let sessionStore: AppSessionStore
    private let loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase
    private let loadHomeMotionHealthUseCase: LoadHomeMotionHealthUseCase
    private let manageHomeMemberUseCase: ManageHomeMemberUseCase
    private let requestHomeHealthAuthorizationUseCase: RequestHomeHealthAuthorizationUseCase
    private let patientContextStore: PatientContextStore
    private let notificationClient: any NotificationClient
    private let logger: Logger

    private let logModule = LogModule.home

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - sessionStore: 会话状态，用于读取当前 `profileID`。
    ///   - loadHomeMedicalOverviewUseCase: 医疗摘要（不含 HealthKit）。
    ///   - loadHomeMotionHealthUseCase: 运动健康（仅本人读 HealthKit）。
    ///   - manageHomeMemberUseCase: 成员的增删改及触发远端同步。
    ///   - requestHomeHealthAuthorizationUseCase: 请求 Apple 健康权限。
    ///   - patientContextStore: 与聊天/病历等共享的当前患者上下文。
    ///   - notificationClient: 非阻塞错误与提示。
    ///   - logger: 结构化日志（耗时、分支，不记录敏感健康数值）。
    init(
        sessionStore: AppSessionStore,
        loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase,
        loadHomeMotionHealthUseCase: LoadHomeMotionHealthUseCase,
        manageHomeMemberUseCase: ManageHomeMemberUseCase,
        requestHomeHealthAuthorizationUseCase: RequestHomeHealthAuthorizationUseCase,
        patientContextStore: PatientContextStore,
        notificationClient: any NotificationClient,
        logger: Logger
    ) {
        self.sessionStore = sessionStore
        self.loadHomeMedicalOverviewUseCase = loadHomeMedicalOverviewUseCase
        self.loadHomeMotionHealthUseCase = loadHomeMotionHealthUseCase
        self.manageHomeMemberUseCase = manageHomeMemberUseCase
        self.requestHomeHealthAuthorizationUseCase = requestHomeHealthAuthorizationUseCase
        self.patientContextStore = patientContextStore
        self.notificationClient = notificationClient
        self.logger = logger
    }

    // MARK: - Loading

    /// 加载或刷新首页：先完成医疗摘要，再加载运动健康；两阶段独立打点 `isLoadingMedical` / `isLoadingMotion`。
    ///
    /// - Parameter syncRemote: 为 `true` 时向服务端拉取医疗快照；切换成员、授权后刷新等场景传 `false` 仅用本地快照重算，减少全量同步。
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

        isLoadingMotion = true
        defer { isLoadingMotion = false }

        let motion: HomeMotionHealthOverview
        do {
            motion = try await loadHomeMotionHealthUseCase.execute(selectedMember: medicalResult.selectedMember)
        } catch {
            logger.warning(
                "运动健康加载失败: \(error.localizedDescription)",
                module: logModule
            )
            motion = HomeMotionHealthOverview(
                healthBasics: [],
                healthAuthorizationStatus: .unavailable,
                isApplicable: medicalResult.selectedMember?.canUseMotionHealthOnHome ?? false
            )
        }

        let loaded = HomeDashboard(
            profile: medicalResult.profile,
            members: medicalResult.members,
            selectedMemberID: medicalResult.selectedMemberID,
            medical: medicalResult.medical,
            motion: motion
        )
        dashboard = loaded
        selectedMemberID = loaded.selectedMember?.id
        patientContextStore.update(members: loaded.members, selectedMemberID: loaded.selectedMemberID)
        errorMessage = nil

        let cost = Date().timeIntervalSince(startedAt)
        logger.info(
            "首页加载完成 cost=\(String(format: "%.3f", cost))s syncRemote=\(syncRemote)",
            module: logModule
        )
    }

    /// 用户主动刷新：强制同步远端医疗快照后再刷新运动健康。
    func refresh() async {
        await load(syncRemote: true)
    }

    // MARK: - Member selection

    /// 切换当前成员并刷新 UI；不拉远端，仅基于本地快照重算医疗卡片并更新运动健康（若为新选中「本人」则读 HealthKit）。
    func selectMember(_ memberID: Int?) {
        selectedMemberID = memberID
        patientContextStore.select(memberID: memberID)
        Task { await load(syncRemote: false) }
    }

    // MARK: - Health authorization

    /// 请求系统健康权限，成功后以本地快照刷新首页（不强制全量拉取医疗快照）。
    func requestHealthAuthorization() async {
        do {
            _ = try await requestHomeHealthAuthorizationUseCase.execute()
            await load(syncRemote: false)
        } catch {
            errorMessage = nil
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.healthAuth")
        }
    }

    // MARK: - Member CRUD

    /// 新增成员；成功后同步远端并刷新首页。
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

    /// 更新成员信息；成功后同步远端并刷新首页。
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

    /// 删除成员；若删的是当前选中成员则清空选中并同步上下文，随后拉远端并刷新首页。
    func deleteMember(_ member: Member) async {
        do {
            try await manageHomeMemberUseCase.delete(member: member)
            if selectedMemberID == member.id {
                selectedMemberID = nil
                patientContextStore.select(memberID: nil)
            }
            await load(syncRemote: true)
        } catch {
            errorMessage = nil
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.member.delete")
        }
    }

#if DEBUG

    /// SwiftUI 预览注入：跳过网络与健康请求，仅展示给定 `HomeDashboard`。
    func injectPreviewDashboard(_ dashboard: HomeDashboard) {
        self.dashboard = dashboard
        self.errorMessage = nil
        self.isLoading = false
        self.isLoadingMedical = false
        self.isLoadingMotion = false
        self.selectedMemberID = dashboard.selectedMember?.id
    }
#endif
}
