#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

/// IOS26-TABBAR-000009：医院服务首页 ViewModel——加载态/缓存态/错误态（Q18/Q19）、
/// 首屏医生卡片前三位（Q12）、医生会话进入守卫与最近会话复用（Q13）。
@MainActor
final class HospitalHomeViewModelTests: XCTestCase {
    private let accountID: Int64 = 42

    // MARK: - 未登录

    func testSignedOutShowsUnavailable() async {
        let context = makeContext(remote: StubHospitalCareRemoteAPI(), signedIn: false)

        await context.viewModel.onAppear()

        XCTAssertEqual(context.viewModel.loadState, .unavailable)
    }

    // MARK: - 首次加载（无缓存）

    func testFirstLoadSuccessShowsLiveContentAndCapsFeaturedAgents() async {
        let remote = StubHospitalCareRemoteAPI()
        let hospitalDTO = HospitalCareTestFixtures.hospitalDTO(name: "天长市中医院")
        remote.hospitalsResult = .success([hospitalDTO])
        remote.departmentsResult = .success([
            HospitalDepartmentPublicDTO(id: UUID(), name: "心内科", sortOrder: 1),
            HospitalDepartmentPublicDTO(id: UUID(), name: "皮肤科", sortOrder: 2)
        ])
        remote.agentsResult = .success((1 ... 5).map {
            HospitalCareTestFixtures.agentDTO(hospitalID: hospitalDTO.id, doctorName: "医生\($0)")
        })
        let context = makeContext(remote: remote)

        await context.viewModel.onAppear()

        XCTAssertEqual(context.viewModel.loadState, .ready)
        XCTAssertEqual(context.viewModel.freshness, .live)
        XCTAssertEqual(context.viewModel.hospital?.name, "天长市中医院")
        XCTAssertEqual(context.viewModel.departments.count, 2)
        XCTAssertEqual(context.viewModel.agentCards.count, 5)
        // Q12：首页首屏最多展示 3 位医生横向卡片，取服务端目录顺序前 3 位。
        XCTAssertEqual(context.viewModel.featuredAgents.count, 3)
        XCTAssertEqual(context.viewModel.featuredAgents.map(\.doctorDisplayName), ["医生1", "医生2", "医生3"])
    }

    func testFirstLoadFailureWithoutCacheShowsUnavailable() async {
        let remote = StubHospitalCareRemoteAPI()
        remote.hospitalsResult = .failure(StubHospitalCareRemoteAPI.StubError.network)
        let context = makeContext(remote: remote)

        await context.viewModel.onAppear()

        // Q18/31.4：无缓存且回源失败显示"医院服务暂不可用"，不展示无来源的医院内容。
        XCTAssertEqual(context.viewModel.loadState, .unavailable)
        XCTAssertNil(context.viewModel.hospital)
    }

    // MARK: - 缓存优先 + 后台刷新

    func testCachedSnapshotShownThenRefreshSuccessTurnsLive() async {
        let cache = HospitalCatalogMemoryCache()
        let cached = HospitalCareTestFixtures.hospitalSummary(name: "旧医院")
        cache.storeHospitals([cached], accountID: accountID)
        let remote = StubHospitalCareRemoteAPI()
        remote.hospitalsResult = .success([HospitalCareTestFixtures.hospitalDTO(id: cached.id, name: "新医院")])
        let context = makeContext(remote: remote, cache: cache)

        await context.viewModel.onAppear()

        // Q18：缓存先展示，后台刷新成功后更新内容并消除缓存提示。
        XCTAssertEqual(context.viewModel.loadState, .ready)
        XCTAssertEqual(context.viewModel.hospital?.name, "新医院")
        XCTAssertEqual(context.viewModel.freshness, .live)
    }

    func testRefreshFailureKeepsCachedContentAndMarksStale() async {
        let cache = HospitalCatalogMemoryCache()
        let cached = HospitalCareTestFixtures.hospitalSummary(name: "缓存医院")
        cache.storeHospitals([cached], accountID: accountID)
        let remote = StubHospitalCareRemoteAPI()
        remote.hospitalsResult = .failure(StubHospitalCareRemoteAPI.StubError.network)
        remote.departmentsResult = .failure(StubHospitalCareRemoteAPI.StubError.network)
        remote.agentsResult = .failure(StubHospitalCareRemoteAPI.StubError.network)
        let context = makeContext(remote: remote, cache: cache)

        await context.viewModel.onAppear()

        // Q19/31.4：后台刷新失败不清空旧数据，标记"当前显示上次数据"。
        XCTAssertEqual(context.viewModel.loadState, .ready)
        XCTAssertEqual(context.viewModel.hospital?.name, "缓存医院")
        XCTAssertEqual(context.viewModel.freshness, .cachedStale)
    }

    // MARK: - 医生会话进入守卫与最近会话复用（Q13）

    func testOpenAgentRequiresSelectedMember() async {
        let remote = StubHospitalCareRemoteAPI()
        let hospitalDTO = HospitalCareTestFixtures.hospitalDTO()
        remote.hospitalsResult = .success([hospitalDTO])
        remote.agentsResult = .success([HospitalCareTestFixtures.agentDTO(hospitalID: hospitalDTO.id)])
        let context = makeContext(remote: remote)
        await context.viewModel.onAppear()
        guard let card = context.viewModel.featuredAgents.first else {
            return XCTFail("期望已有医生卡片")
        }

        let threadID = await context.viewModel.openAgent(card)

        XCTAssertNil(threadID)
        XCTAssertEqual(context.viewModel.actionError, "请先选择就诊人")
    }

    func testOpenAgentWithRecentConversationReturnsExistingThread() async {
        let remote = StubHospitalCareRemoteAPI()
        let hospitalDTO = HospitalCareTestFixtures.hospitalDTO()
        remote.hospitalsResult = .success([hospitalDTO])
        let agentDTO = HospitalCareTestFixtures.agentDTO(hospitalID: hospitalDTO.id)
        remote.agentsResult = .success([agentDTO])
        let existingThreadID = UUID()
        remote.conversationsResult = .success([
            HospitalCareTestFixtures.conversationDTO(
                threadID: existingThreadID,
                agentID: agentDTO.id,
                memberID: 7,
                hospitalID: hospitalDTO.id
            )
        ])
        let context = makeContext(remote: remote)
        context.memberContextStore.update(members: [Member(id: 7, name: "测试成员")], selectedMemberID: 7)
        await context.viewModel.onAppear()
        guard let card = context.viewModel.featuredAgents.first else {
            return XCTFail("期望已有医生卡片")
        }
        XCTAssertTrue(card.hasRecentConversation)

        let threadID = await context.viewModel.openAgent(card)

        // Q13：已有最近会话时直接复用既有 thread，不新建会话。
        XCTAssertEqual(threadID, existingThreadID)
        XCTAssertNil(context.viewModel.actionError)
    }

    // MARK: - 装配

    private struct TestContext {
        let viewModel: HospitalHomeViewModel
        let memberContextStore: MemberContextStore
    }

    private func makeContext(
        remote: StubHospitalCareRemoteAPI,
        cache: HospitalCatalogMemoryCache = HospitalCatalogMemoryCache(),
        signedIn: Bool = true
    ) -> TestContext {
        let scopeStore = HospitalConversationScopeStore()
        let engine = SparkNetworkEngine(baseURL: URL(string: "https://example.com")!)
        let configuration = SparkBackendConfiguration(engine: engine)
        let concreteRemote = HospitalCareRemoteAPI(configuration: configuration)
        let knowledgeRepository = HospitalKnowledgeInMemoryRepository()
        let dependencies = HospitalCareFeatureDependencies(
            remoteAPI: concreteRemote,
            catalogCache: cache,
            scopeStore: scopeStore,
            loadDirectory: LoadHospitalAgentDirectoryUseCase(remoteAPI: remote, catalogCache: cache),
            resolveDemoHospital: ResolveDemoHospitalUseCase(remoteAPI: remote, catalogCache: cache),
            resolveOrCreate: ResolveOrCreateHospitalConversationUseCase(remoteAPI: concreteRemote, scopeStore: scopeStore),
            resolveScope: ResolveHospitalConversationScopeUseCase(remoteAPI: remote, scopeStore: scopeStore),
            hydrateScopes: HydrateHospitalConversationScopesUseCase(remoteAPI: remote, scopeStore: scopeStore),
            loadDoctorProfile: LoadHospitalDoctorProfileUseCase(remoteAPI: remote, catalogCache: cache),
            fetchContext: FetchHospitalConversationContextUseCase(remoteAPI: remote),
            knowledgeSync: HospitalKnowledgeSyncCoordinator(remoteAPI: remote, repository: knowledgeRepository),
            knowledgeRepository: knowledgeRepository
        )
        let memberContextStore = MemberContextStore()
        let sessionStore = AppSessionStore(
            restoreSessionUseCase: RestoreSessionUseCase(authRepository: StubAuthRepository())
        )
        if signedIn {
            sessionStore.setAuthenticated(UserSession(
                accountID: accountID,
                email: "test@example.com",
                displayName: "测试账号",
                signedInAt: Date(),
                signInMethod: .phone
            ))
        } else {
            sessionStore.setSignedOut()
        }
        return TestContext(
            viewModel: HospitalHomeViewModel(
                dependencies: dependencies,
                memberContextStore: memberContextStore,
                sessionStore: sessionStore
            ),
            memberContextStore: memberContextStore
        )
    }
}

/// 仅满足 `AppSessionStore` 装配；测试通过 `setAuthenticated` / `setSignedOut` 直接控制状态。
private final class StubAuthRepository: AuthRepository, @unchecked Sendable {
    enum StubError: Error { case unsupported }

    func restoreSession() async -> UserSession? { nil }
    func signInWithApple(payload: AppleSignInPayload) async throws -> UserSession { throw StubError.unsupported }
    func signInWithDevice() async throws -> UserSession { throw StubError.unsupported }
    func requestPhoneOTP(phoneNumber: String) async throws -> PhoneOTPRequestContext { throw StubError.unsupported }
    func signInWithPhoneOTP(phoneNumber: String, verificationCode: String, otpID: String) async throws -> UserSession {
        throw StubError.unsupported
    }
    func signOut() async throws {}
}
#endif
