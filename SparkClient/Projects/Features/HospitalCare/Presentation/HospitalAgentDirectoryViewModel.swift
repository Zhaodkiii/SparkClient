import Foundation
import Combine

@MainActor
final class HospitalAgentDirectoryViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case empty
        /// 服务不可用（未登录或无依赖），与目录请求失败区分。
        case unavailable
        /// 医院目录加载成功，但不存在 code == 000001 的演示医院。
        case demoHospitalMissing
        /// 医院目录请求失败（停留在院内分段并展示重试，不降级回普通列表）。
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var hospital: HospitalSummary?
    @Published private(set) var departments: [HospitalDepartmentSummary] = []
    @Published var selectedDepartmentID: UUID?
    @Published var keyword = ""
    @Published private(set) var cards: [HospitalAgentCard] = []
    @Published private(set) var isRefreshing = false
    @Published var openingAgentID: UUID?
    @Published var actionError: String?

    private let dependencies: HospitalCareFeatureDependencies
    private let memberContextStore: MemberContextStore
    private let sessionStore: AppSessionStore
    private var searchTask: Task<Void, Never>?

    var isAvailable: Bool {
        hospital != nil && loadState != .unavailable
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
        await reload(force: false)
    }

    func retry() async {
        await reload(force: true)
    }

    func selectDepartment(_ departmentID: UUID?) async {
        selectedDepartmentID = departmentID
        await reloadAgents()
    }

    func updateKeyword(_ text: String) {
        keyword = text
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard Task.isCancelled == false else { return }
            await self?.reloadAgents()
        }
    }

    func openCard(_ card: HospitalAgentCard) async -> UUID? {
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

    private func reload(force: Bool) async {
        guard let accountID else {
            loadState = .unavailable
            return
        }
        if force == false, hospital != nil, loadState == .ready || loadState == .empty {
            await reloadAgents()
            return
        }
        loadState = .loading
        let resolution = await dependencies.resolveDemoHospital.execute(
            accountID: accountID,
            forceRefresh: force
        )
        switch resolution {
        case .resolved(let demo):
            hospital = demo
            departments = (try? await dependencies.loadDirectory.loadDepartments(
                accountID: accountID,
                hospitalID: demo.id
            )) ?? []
            await reloadAgents()
        case .missing:
            hospital = nil
            departments = []
            cards = []
            loadState = .demoHospitalMissing
        case .failed:
            hospital = nil
            departments = []
            cards = []
            loadState = .failed("医院目录加载失败，请检查网络后重试")
        }
    }

    private func reloadAgents() async {
        guard let hospital, let accountID else {
            loadState = .unavailable
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let memberID = memberContextStore.context.selectedMemberID
            cards = try await dependencies.loadDirectory.loadAgents(
                accountID: accountID,
                hospitalID: hospital.id,
                departmentID: selectedDepartmentID,
                keyword: keyword,
                memberID: memberID
            )
            loadState = cards.isEmpty ? .empty : .ready
        } catch {
            if cards.isEmpty {
                loadState = .failed(error.localizedDescription)
            }
        }
    }
}
