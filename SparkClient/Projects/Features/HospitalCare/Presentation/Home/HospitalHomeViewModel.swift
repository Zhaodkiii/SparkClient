import Combine
import Foundation

/// IOS26-TABBAR-000009：医院服务首页视图模型。
/// 复用 HospitalCare 既有医院/科室/医生智能体目录与会话契约，不新建医院业务实体。
/// 加载策略（Q18/Q19）：有缓存先展示缓存并后台刷新；无缓存且回源失败显示"医院服务暂不可用"。
@MainActor
final class HospitalHomeViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        /// 首次加载（无缓存可展示），页面显示骨架。
        case loading
        /// 已有可展示内容（实时或缓存）。
        case ready
        /// 无缓存且医院列表/配置回源失败：不展示无来源的医院内容。
        case unavailable
    }

    /// 缓存新鲜度（Q19）：驱动"已使用缓存数据，正在更新"与"当前显示上次数据"轻量提示。
    enum Freshness: Equatable {
        /// 最新服务端数据，不显示提示。
        case live
        /// 正在展示缓存，后台刷新中。
        case cachedRefreshing
        /// 后台刷新失败，保留上次数据。
        case cachedStale
    }

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var freshness: Freshness = .live
    @Published private(set) var hospital: HospitalSummary?
    @Published private(set) var departments: [HospitalDepartmentSummary] = []
    @Published private(set) var agentCards: [HospitalAgentCard] = []
    @Published private(set) var openingAgentID: UUID?
    @Published var actionError: String?

    private let dependencies: HospitalCareFeatureDependencies
    private let memberContextStore: MemberContextStore
    private let sessionStore: AppSessionStore
    private var hasLoadedOnce = false

    /// Q12：首页展示 3 位医生横向卡片，取服务端目录顺序前 3 位。
    /// 注：不足 3 位时的演示医生补足策略尚未确认（工单第 32 节），本期只展示真实已发布医生。
    var featuredAgents: [HospitalAgentCard] {
        Array(agentCards.prefix(3))
    }

    init(
        dependencies: HospitalCareFeatureDependencies,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore
    ) {
        self.dependencies = dependencies
        self.memberContextStore = memberContextStore
        self.sessionStore = sessionStore
    }

    func onAppear() async {
        guard hasLoadedOnce == false else { return }
        hasLoadedOnce = true
        await load()
    }

    func retry() async {
        await load()
    }

    /// 成员切换后仅重算医生卡片（最近会话归属随成员变化），不打断页面其他内容与滚动位置。
    func reloadAgentsForCurrentMember() async {
        guard let accountID, let hospital, loadState == .ready else { return }
        if let cards = try? await dependencies.loadDirectory.loadAgents(
            accountID: accountID,
            hospitalID: hospital.id,
            departmentID: nil,
            keyword: "",
            memberID: memberContextStore.context.selectedMemberID
        ) {
            agentCards = cards
        }
    }

    /// 点击医生卡片 / "去问 AI 助手"：复用医院会话创建/继续逻辑，绑定 hospitalID + agentID + memberID。
    func openAgent(_ card: HospitalAgentCard) async -> UUID? {
        guard let accountID else {
            actionError = "请先登录后再咨询医生智能体"
            return nil
        }
        guard let memberID = memberContextStore.context.selectedMemberID else {
            actionError = "请先选择就诊人"
            return nil
        }
        guard let hospital else { return nil }
        openingAgentID = card.id
        actionError = nil
        defer { openingAgentID = nil }
        do {
            return try await dependencies.resolveOrCreate.execute(
                agentID: card.id,
                memberID: memberID,
                hospitalID: hospital.id,
                accountID: accountID,
                recentThreadID: card.recentThreadID
            )
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }

    private var accountID: Int64? {
        if case .signedIn(let session) = sessionStore.state {
            return session.accountID
        }
        return nil
    }

    private func load() async {
        guard let accountID else {
            loadState = .unavailable
            return
        }

        // Q18：有缓存先展示缓存，再后台刷新；无缓存进入首次加载骨架。
        if let cachedHospital = dependencies.catalogCache.hospitals(accountID: accountID)?.first {
            applyCachedSnapshot(accountID: accountID, hospital: cachedHospital)
            loadState = .ready
            freshness = .cachedRefreshing
        } else if hospital == nil {
            loadState = .loading
        } else {
            freshness = .cachedRefreshing
        }

        await refresh(accountID: accountID)
    }

    /// 用内存缓存立即拼装首页内容；医生卡片的"最近会话"信息等待刷新补全。
    private func applyCachedSnapshot(accountID: Int64, hospital: HospitalSummary) {
        self.hospital = hospital
        departments = dependencies.catalogCache.departments(accountID: accountID, hospitalID: hospital.id) ?? []
        if agentCards.isEmpty {
            agentCards = cachedAgentCards(accountID: accountID, hospitalID: hospital.id)
        }
    }

    private func cachedAgentCards(accountID: Int64, hospitalID: UUID) -> [HospitalAgentCard] {
        (dependencies.catalogCache.agents(accountID: accountID, hospitalID: hospitalID) ?? []).map { dto in
            HospitalAgentCard(
                id: dto.id,
                hospitalID: dto.hospitalId,
                name: dto.name,
                publicSummary: dto.publicSummary ?? "",
                serviceBoundary: dto.serviceBoundary ?? "",
                doctorID: dto.doctor.id,
                doctorDisplayName: dto.doctor.displayName,
                doctorTitle: dto.doctor.title ?? "",
                doctorAvatarURL: dto.doctor.avatarUrl ?? "",
                specialties: dto.doctor.specialties ?? [],
                departmentID: dto.department?.id,
                departmentName: dto.department?.name ?? "",
                hasRecentConversation: false,
                recentThreadID: nil
            )
        }
    }

    /// 后台/显式刷新：成功更新内容并消除缓存提示；失败保留旧内容并提示"当前显示上次数据"。
    /// 后台刷新不阻断浏览，也不把页面滚回顶部（Q21）。
    private func refresh(accountID: Int64) async {
        let resolution = await dependencies.resolveDemoHospital.execute(
            accountID: accountID,
            forceRefresh: true
        )
        switch resolution {
        case .resolved(let resolved):
            hospital = resolved
            if let loadedDepartments = try? await dependencies.loadDirectory.loadDepartments(
                accountID: accountID,
                hospitalID: resolved.id,
                forceRefresh: true
            ) {
                departments = loadedDepartments
            }
            var refreshFailed = false
            do {
                agentCards = try await dependencies.loadDirectory.loadAgents(
                    accountID: accountID,
                    hospitalID: resolved.id,
                    departmentID: nil,
                    keyword: "",
                    memberID: memberContextStore.context.selectedMemberID,
                    forceRefresh: true
                )
            } catch {
                refreshFailed = true
            }
            loadState = .ready
            freshness = refreshFailed ? .cachedStale : .live
        case .missing, .failed:
            if hospital != nil {
                freshness = .cachedStale
            } else {
                // 无医院上下文时不展示固定医院、固定科室和演示医生内容（Q18）。
                loadState = .unavailable
            }
        }
    }
}
