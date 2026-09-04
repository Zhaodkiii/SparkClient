#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

/// CHAT-000055：Q30 取医院列表第一家 + Q31 空/无缓存失败回退 + 目录缓存 stale-while-revalidate。
final class HospitalCareDirectoryUseCaseTests: XCTestCase {
    private let accountID: Int64 = 42

    // MARK: - Q30：取列表第一家（服务端返回顺序）

    func testDemoHospitalResolvedByFirstRowNotCode() async {
        let remote = StubHospitalCareRemoteAPI()
        let first = HospitalCareTestFixtures.hospitalDTO(code: "000009", name: "首位医院")
        let second = HospitalCareTestFixtures.hospitalDTO(code: "000001", name: "次位医院")
        // Q30：不使用 code/名称匹配，必须取服务端顺序第一家。
        remote.hospitalsResult = .success([first, second])
        let useCase = ResolveDemoHospitalUseCase(
            remoteAPI: remote,
            catalogCache: HospitalCatalogMemoryCache()
        )

        let resolution = await useCase.execute(accountID: accountID)

        guard case .resolved(let hospital) = resolution else {
            return XCTFail("期望 resolved，实际 \(resolution)")
        }
        XCTAssertEqual(hospital.id, first.id)
        XCTAssertEqual(hospital.name, "首位医院")
    }

    // MARK: - Q31：列表空 / 无缓存失败

    func testDemoHospitalMissingWhenListEmpty() async {
        let remote = StubHospitalCareRemoteAPI()
        remote.hospitalsResult = .success([])
        let useCase = ResolveDemoHospitalUseCase(
            remoteAPI: remote,
            catalogCache: HospitalCatalogMemoryCache()
        )

        let resolution = await useCase.execute(accountID: accountID)

        XCTAssertEqual(resolution, .missing)
    }

    func testDemoHospitalFailedWhenRequestFailsWithoutCache() async {
        let remote = StubHospitalCareRemoteAPI()
        remote.hospitalsResult = .failure(StubHospitalCareRemoteAPI.StubError.network)
        let useCase = ResolveDemoHospitalUseCase(
            remoteAPI: remote,
            catalogCache: HospitalCatalogMemoryCache()
        )

        let resolution = await useCase.execute(accountID: accountID)

        XCTAssertEqual(resolution, .failed)
    }

    func testDemoHospitalFallsBackToCacheWhenRefreshFails() async {
        let cache = HospitalCatalogMemoryCache()
        let first = HospitalCareTestFixtures.hospitalSummary(code: "000009", name: "首位医院")
        cache.storeHospitals([first], accountID: accountID)
        let remote = StubHospitalCareRemoteAPI()
        remote.hospitalsResult = .failure(StubHospitalCareRemoteAPI.StubError.network)
        let useCase = ResolveDemoHospitalUseCase(remoteAPI: remote, catalogCache: cache)

        let resolution = await useCase.execute(accountID: accountID, forceRefresh: true)

        XCTAssertEqual(resolution, .resolved(first))
    }

    // MARK: - SWR：命中缓存立即返回，后台静默刷新

    func testDemoHospitalCacheHitReturnsImmediatelyAndRefreshesInBackground() async throws {
        let cache = HospitalCatalogMemoryCache(stalenessInterval: 0)
        let stale = HospitalCareTestFixtures.hospitalSummary(code: "old", name: "旧首位")
        cache.storeHospitals([stale], accountID: accountID)
        let remote = StubHospitalCareRemoteAPI()
        let fresh = HospitalCareTestFixtures.hospitalDTO(code: "new", name: "新首位")
        remote.hospitalsResult = .success([fresh])
        let useCase = ResolveDemoHospitalUseCase(remoteAPI: remote, catalogCache: cache)

        // stalenessInterval = 0 → 缓存立即 stale：先返回旧值，后台刷新写新值。
        let resolution = await useCase.execute(accountID: accountID)
        XCTAssertEqual(resolution, .resolved(stale))

        // 等待后台静默刷新落缓存。
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if cache.hospitals(accountID: accountID)?.first?.name == "新首位" { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(cache.hospitals(accountID: accountID)?.first?.name, "新首位")
    }

    func testAgentsDirectoryServesCacheWhenRefreshFails() async throws {
        let hospitalID = UUID()
        let cache = HospitalCatalogMemoryCache()
        let cachedDTO = HospitalCareTestFixtures.agentDTO(hospitalID: hospitalID, doctorName: "缓存医生")
        cache.storeAgents([cachedDTO], accountID: accountID, hospitalID: hospitalID)
        let remote = StubHospitalCareRemoteAPI()
        remote.agentsResult = .failure(StubHospitalCareRemoteAPI.StubError.network)
        let useCase = LoadHospitalAgentDirectoryUseCase(remoteAPI: remote, catalogCache: cache)

        // 缓存新鲜（未过期）：直接命中，不触发网络失败。
        let cards = try await useCase.loadAgents(
            accountID: accountID,
            hospitalID: hospitalID,
            departmentID: nil,
            keyword: "",
            memberID: nil
        )

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].doctorDisplayName, "缓存医生")
    }

    // MARK: - 目录选主与排序（沿用 CHAT-000054 语义）

    func testDirectoryDoesNotDeduplicateAgentsForSameDoctor() async throws {
        let doctorID = UUID()
        let hospitalID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        // 服务端已为每位医生返回唯一已发布智能体；即使返回多条，iOS 也不再做选主丢弃。
        remote.agentsResult = .success([
            HospitalCareTestFixtures.agentDTO(hospitalID: hospitalID, doctorID: doctorID, doctorName: "李医生"),
            HospitalCareTestFixtures.agentDTO(hospitalID: hospitalID, doctorID: doctorID, doctorName: "李医生")
        ])
        let useCase = LoadHospitalAgentDirectoryUseCase(
            remoteAPI: remote,
            catalogCache: HospitalCatalogMemoryCache()
        )

        let cards = try await useCase.loadAgents(
            accountID: accountID,
            hospitalID: hospitalID,
            departmentID: nil,
            keyword: "",
            memberID: nil
        )

        XCTAssertEqual(cards.count, 2)
    }

    func testDirectoryConsultedFirstKeepsServerOrderWithinGroups() async throws {
        let hospitalID = UUID()
        let agentA = UUID()
        let agentB = UUID()
        let agentC = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.agentsResult = .success([
            HospitalCareTestFixtures.agentDTO(id: agentA, hospitalID: hospitalID, doctorName: "医生A"),
            HospitalCareTestFixtures.agentDTO(id: agentB, hospitalID: hospitalID, doctorName: "医生B"),
            HospitalCareTestFixtures.agentDTO(id: agentC, hospitalID: hospitalID, doctorName: "医生C")
        ])
        remote.conversationsResult = .success([
            HospitalCareTestFixtures.conversationDTO(agentID: agentB, memberID: 7)
        ])
        let useCase = LoadHospitalAgentDirectoryUseCase(
            remoteAPI: remote,
            catalogCache: HospitalCatalogMemoryCache()
        )

        let cards = try await useCase.loadAgents(
            accountID: accountID,
            hospitalID: hospitalID,
            departmentID: nil,
            keyword: "",
            memberID: 7
        )

        // 已咨询的 B 提前；A/C 保持服务端返回顺序。
        XCTAssertEqual(cards.map(\.id), [agentB, agentA, agentC])
        XCTAssertTrue(cards[0].hasRecentConversation)
        XCTAssertNotNil(cards[0].recentThreadID)
        XCTAssertFalse(cards[1].hasRecentConversation)
    }
    // MARK: - BACKOFFICE-HOSPITAL-AGENT-000002：智能体头像映射

    func testAgentAvatarPrefersServerResolvedURL() async throws {
        let hospitalID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.agentsResult = .success([
            HospitalCareTestFixtures.agentDTO(
                hospitalID: hospitalID,
                doctorName: "王医生",
                doctorAvatarUrl: "https://oss.test/doctor.webp?v=1",
                agentAvatarUrl: "https://oss.test/agent.webp?v=2",
                agentAvatarVersion: "custom:1:abc"
            )
        ])
        let useCase = LoadHospitalAgentDirectoryUseCase(
            remoteAPI: remote,
            catalogCache: HospitalCatalogMemoryCache()
        )

        let cards = try await useCase.loadAgents(
            accountID: accountID,
            hospitalID: hospitalID,
            departmentID: nil,
            keyword: "",
            memberID: nil
        )

        XCTAssertEqual(cards.first?.avatarURL, "https://oss.test/agent.webp?v=2")
        XCTAssertEqual(cards.first?.avatarVersion, "custom:1:abc")
    }

    func testAgentAvatarFallsBackToDoctorAvatar() async throws {
        let hospitalID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.agentsResult = .success([
            HospitalCareTestFixtures.agentDTO(
                hospitalID: hospitalID,
                doctorName: "王医生",
                doctorAvatarUrl: "https://oss.test/doctor.webp?v=1"
            )
        ])
        let useCase = LoadHospitalAgentDirectoryUseCase(
            remoteAPI: remote,
            catalogCache: HospitalCatalogMemoryCache()
        )

        let cards = try await useCase.loadAgents(
            accountID: accountID,
            hospitalID: hospitalID,
            departmentID: nil,
            keyword: "",
            memberID: nil
        )

        XCTAssertEqual(cards.first?.avatarURL, "https://oss.test/doctor.webp?v=1")
        XCTAssertEqual(cards.first?.avatarVersion, "")
    }

    func testAgentAvatarEmptyWhenNeitherAvailable() async throws {
        let hospitalID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.agentsResult = .success([
            HospitalCareTestFixtures.agentDTO(hospitalID: hospitalID, doctorName: "王医生")
        ])
        let useCase = LoadHospitalAgentDirectoryUseCase(
            remoteAPI: remote,
            catalogCache: HospitalCatalogMemoryCache()
        )

        let cards = try await useCase.loadAgents(
            accountID: accountID,
            hospitalID: hospitalID,
            departmentID: nil,
            keyword: "",
            memberID: nil
        )

        XCTAssertEqual(cards.first?.avatarURL, "")
    }
}
#endif
