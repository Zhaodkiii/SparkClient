#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

/// CHAT-000058 C-003/C-017/C-018：先取专用配置 → 再创建/复用 Thread → 校验 scope。
@MainActor
final class HospitalResolveOrCreateConversationTests: XCTestCase {
    private let accountID: Int64 = 42
    private let memberID = 7

    private func makeScopeStore() -> HospitalConversationScopeStore {
        let suite = "HospitalResolveOrCreateConversationTests.\(UUID().uuidString)"
        return HospitalConversationScopeStore(defaults: UserDefaults(suiteName: suite)!)
    }

    private func makeConfigStore(
        keychain: InMemoryHospitalAgentRuntimeConfigKeychain = InMemoryHospitalAgentRuntimeConfigKeychain()
    ) -> HospitalAgentRuntimeConfigStore {
        let suite = "HospitalResolveOrCreateConversationTests.\(UUID().uuidString)"
        return HospitalAgentRuntimeConfigStore(
            keychain: keychain,
            defaults: UserDefaults(suiteName: suite)!
        )
    }

    @MainActor
    private func makeUseCase(
        remote: StubHospitalCareRemoteAPI,
        scopeStore: HospitalConversationScopeStore? = nil,
        configStore: HospitalAgentRuntimeConfigStore? = nil,
        repository: RecordingChatRepository = RecordingChatRepository(),
        stateStore: ChatStateStore? = nil
    ) -> (
        ResolveOrCreateHospitalConversationUseCase,
        HospitalConversationScopeStore,
        HospitalAgentRuntimeConfigStore,
        RecordingChatRepository,
        ChatStateStore
    ) {
        let scopes = scopeStore ?? makeScopeStore()
        let configs = configStore ?? makeConfigStore()
        let chatStateStore = stateStore ?? ChatStateStore()
        let useCase = ResolveOrCreateHospitalConversationUseCase(
            remoteAPI: remote,
            scopeStore: scopes,
            fetchRuntimeConfig: FetchHospitalAgentRuntimeConfigUseCase(remoteAPI: remote),
            runtimeConfigStore: configs,
            chatRepository: repository,
            chatStateStore: chatStateStore
        )
        return (useCase, scopes, configs, repository, chatStateStore)
    }

    private func createdResponse(
        threadID: UUID,
        agentID: UUID,
        hospitalID: UUID,
        memberID: Int,
        bindingID: Int? = 130,
        bindingVersion: Int? = 1788503258
    ) -> HospitalCreateConversationResponseDTO {
        var conversation = HospitalConversationDTO(
            threadId: threadID,
            agent: HospitalConversationAgentDTO(id: agentID, name: "智能体", publicationStatus: "published"),
            memberId: memberID,
            hospital: HospitalCareTestFixtures.hospitalDTO(id: hospitalID)
        )
        conversation.bindingId = bindingID
        conversation.bindingVersion = bindingVersion
        return HospitalCreateConversationResponseDTO(
            threadId: threadID,
            thread: HospitalCareTestFixtures.remoteThreadDTO(threadID: threadID, memberID: memberID),
            conversation: conversation,
            initialMessages: [HospitalCareTestFixtures.remoteSystemMessageDTO(threadID: threadID)]
        )
    }

    // MARK: - 配置失败不创建 Thread（C-003/C-017）

    func testConfigFetchFailureDoesNotCreateThread() async {
        let remote = StubHospitalCareRemoteAPI()
        remote.runtimeConfigResult = .failure(StubHospitalCareRemoteAPI.StubError.network)
        remote.createConversationResult = .success(createdResponse(
            threadID: UUID(), agentID: UUID(), hospitalID: UUID(), memberID: memberID
        ))
        let (useCase, _, _, _, _) = makeUseCase(remote: remote)

        do {
            _ = try await useCase.execute(
                agentID: UUID(), memberID: memberID, hospitalID: UUID(),
                accountID: accountID, recentThreadID: nil
            )
            XCTFail("配置查询失败必须抛错，不得创建 Thread")
        } catch {
            XCTAssertEqual(remote.createConversationCallCount, 0)
            XCTAssertEqual(remote.fetchRuntimeConfigCallCount, 1)
        }
    }

    // MARK: - 配置成功才创建 Thread，并写入 scope

    func testConfigSuccessThenCreatesThreadAndRemembersScope() async throws {
        let agentID = UUID()
        let hospitalID = UUID()
        let threadID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.runtimeConfigResult = .success(HospitalCareTestFixtures.runtimeConfigDTO(
            agentID: agentID, hospitalID: hospitalID, memberID: memberID
        ))
        remote.createConversationResult = .success(createdResponse(
            threadID: threadID, agentID: agentID, hospitalID: hospitalID, memberID: memberID
        ))
        let (useCase, scopeStore, configStore, repository, stateStore) = makeUseCase(remote: remote)

        let created = try await useCase.execute(
            agentID: agentID, memberID: memberID, hospitalID: hospitalID,
            accountID: accountID, recentThreadID: nil
        )

        XCTAssertEqual(created, threadID)
        XCTAssertEqual(remote.fetchRuntimeConfigCallCount, 1)
        XCTAssertEqual(remote.createConversationCallCount, 1)
        let scope = scopeStore.scope(for: threadID, accountID: accountID)
        XCTAssertEqual(scope?.agentID, agentID)
        XCTAssertEqual(scope?.memberID, memberID)
        XCTAssertEqual(scope?.hospitalID, hospitalID)
        let upserted = await repository.upsertedThreads
        XCTAssertEqual(upserted.map(\.id), [threadID])
        let consumed = stateStore.takeHospitalInitialMessages(for: threadID)
        XCTAssertEqual(consumed?.count, 1)
        XCTAssertNil(stateStore.takeHospitalInitialMessages(for: threadID))
        // 配置已写入 store，供会话页直接使用（内存命中）。
        XCTAssertNotNil(configStore.cachedConfig(for: HospitalAgentRuntimeConfigStore.Scope(
            accountID: accountID, hospitalID: hospitalID, memberID: memberID, agentID: agentID
        )))
    }

    // MARK: - Keychain/内存命中时跳过服务端查询（C-012）

    func testCachedConfigSkipsFetchButStillCreatesThread() async throws {
        let agentID = UUID()
        let hospitalID = UUID()
        let threadID = UUID()
        let keychain = InMemoryHospitalAgentRuntimeConfigKeychain()
        let configStore = makeConfigStore(keychain: keychain)
        configStore.save(
            HospitalCareTestFixtures.runtimeConfig(agentID: agentID, hospitalID: hospitalID, memberID: memberID),
            accountID: accountID
        )
        let remote = StubHospitalCareRemoteAPI()
        // runtimeConfigResult 为 nil：一旦发起 fetch 即抛 network。
        remote.createConversationResult = .success(createdResponse(
            threadID: threadID, agentID: agentID, hospitalID: hospitalID, memberID: memberID
        ))
        let (useCase, _, _, _, _) = makeUseCase(remote: remote, configStore: configStore)

        let created = try await useCase.execute(
            agentID: agentID, memberID: memberID, hospitalID: hospitalID,
            accountID: accountID, recentThreadID: nil
        )

        XCTAssertEqual(created, threadID)
        XCTAssertEqual(remote.fetchRuntimeConfigCallCount, 0)
        XCTAssertEqual(remote.createConversationCallCount, 1)
    }

    // MARK: - 复用最近 Thread 同样先要求配置成功

    func testRecentThreadReuseStillRequiresConfig() async throws {
        let agentID = UUID()
        let hospitalID = UUID()
        let recentThreadID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.runtimeConfigResult = .success(HospitalCareTestFixtures.runtimeConfigDTO(
            agentID: agentID, hospitalID: hospitalID, memberID: memberID
        ))
        let (useCase, scopeStore, _, repository, stateStore) = makeUseCase(remote: remote)

        let resolved = try await useCase.execute(
            agentID: agentID, memberID: memberID, hospitalID: hospitalID,
            accountID: accountID, recentThreadID: recentThreadID
        )

        XCTAssertEqual(resolved, recentThreadID)
        XCTAssertEqual(remote.createConversationCallCount, 0)
        XCTAssertEqual(scopeStore.scope(for: recentThreadID, accountID: accountID)?.agentID, agentID)
        let upserted = await repository.upsertedThreads
        XCTAssertTrue(upserted.isEmpty)
        XCTAssertNil(stateStore.takeHospitalInitialMessages(for: recentThreadID))
    }

    func testRecentConsultationThreadIsNotReusedForAgentChat() async throws {
        let agentID = UUID()
        let hospitalID = UUID()
        let consultThreadID = UUID()
        let createdThreadID = UUID()
        let consultID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.runtimeConfigResult = .success(HospitalCareTestFixtures.runtimeConfigDTO(
            agentID: agentID, hospitalID: hospitalID, memberID: memberID
        ))
        remote.createConversationResult = .success(createdResponse(
            threadID: createdThreadID, agentID: agentID, hospitalID: hospitalID, memberID: memberID
        ))
        let scopeStore = makeScopeStore()
        scopeStore.remember(
            HospitalConversationScope(
                threadID: consultThreadID,
                agentID: agentID,
                memberID: memberID,
                hospitalID: hospitalID,
                consultationID: consultID,
                consultNo: "C202609050001"
            ),
            accountID: accountID
        )
        let (useCase, storedScopes, _, _, _) = makeUseCase(remote: remote, scopeStore: scopeStore)

        let resolved = try await useCase.execute(
            agentID: agentID, memberID: memberID, hospitalID: hospitalID,
            accountID: accountID, recentThreadID: consultThreadID
        )

        XCTAssertEqual(resolved, createdThreadID)
        XCTAssertEqual(remote.createConversationCallCount, 1)
        XCTAssertEqual(storedScopes.scope(for: consultThreadID, accountID: accountID)?.consultationID, consultID)
        XCTAssertNil(storedScopes.scope(for: createdThreadID, accountID: accountID)?.consultationID)
    }

    // MARK: - scope 不一致视为失败（C-017）

    func testScopeMismatchThrows() async {
        let agentID = UUID()
        let hospitalID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.runtimeConfigResult = .success(HospitalCareTestFixtures.runtimeConfigDTO(
            agentID: agentID, hospitalID: hospitalID, memberID: memberID
        ))
        remote.createConversationResult = .success(createdResponse(
            threadID: UUID(), agentID: UUID(), hospitalID: hospitalID, memberID: memberID
        ))
        let (useCase, scopeStore, _, _, stateStore) = makeUseCase(remote: remote)

        do {
            _ = try await useCase.execute(
                agentID: agentID, memberID: memberID, hospitalID: hospitalID,
                accountID: accountID, recentThreadID: nil
            )
            XCTFail("scope 不一致必须抛错")
        } catch let error as HospitalConversationResolveError {
            XCTAssertEqual(error, .scopeMismatch)
        } catch {
            XCTFail("非预期错误：\(error)")
        }
        XCTAssertTrue(scopeStore.scope(for: UUID(), accountID: accountID) == nil)
        XCTAssertNil(stateStore.takeHospitalInitialMessages(for: UUID()))
    }

    // MARK: - 绑定不一致按配置失效处理（C-018/Q19）

    func testBindingMismatchDeletesCachedConfigAndThrows() async {
        let agentID = UUID()
        let hospitalID = UUID()
        let keychain = InMemoryHospitalAgentRuntimeConfigKeychain()
        let configStore = makeConfigStore(keychain: keychain)
        let remote = StubHospitalCareRemoteAPI()
        remote.runtimeConfigResult = .success(HospitalCareTestFixtures.runtimeConfigDTO(
            agentID: agentID, hospitalID: hospitalID, memberID: memberID,
            bindingID: 130, bindingVersion: 1788503258
        ))
        remote.createConversationResult = .success(createdResponse(
            threadID: UUID(), agentID: agentID, hospitalID: hospitalID, memberID: memberID,
            bindingID: 999, bindingVersion: 1
        ))
        let (useCase, _, _, _, _) = makeUseCase(remote: remote, configStore: configStore)

        do {
            _ = try await useCase.execute(
                agentID: agentID, memberID: memberID, hospitalID: hospitalID,
                accountID: accountID, recentThreadID: nil
            )
            XCTFail("绑定不一致必须抛错")
        } catch let error as HospitalConversationResolveError {
            XCTAssertEqual(error, .bindingMismatch)
        } catch {
            XCTFail("非预期错误：\(error)")
        }
        XCTAssertNil(configStore.cachedConfig(for: HospitalAgentRuntimeConfigStore.Scope(
            accountID: accountID, hospitalID: hospitalID, memberID: memberID, agentID: agentID
        )))
    }

    // MARK: - 配置身份与请求不一致时按配置失效（身份串扰防护）

    func testConfigIdentityMismatchDoesNotCreateThread() async {
        let agentID = UUID()
        let hospitalID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        // 服务端返回另一个 agent 的配置。
        remote.runtimeConfigResult = .success(HospitalCareTestFixtures.runtimeConfigDTO(
            agentID: UUID(), hospitalID: hospitalID, memberID: memberID
        ))
        let (useCase, _, _, _, _) = makeUseCase(remote: remote)

        do {
            _ = try await useCase.execute(
                agentID: agentID, memberID: memberID, hospitalID: hospitalID,
                accountID: accountID, recentThreadID: nil
            )
            XCTFail("配置身份不一致必须失败")
        } catch let error as HospitalAgentRuntimeConfigError {
            XCTAssertEqual(error, .runtimeConfigInvalid)
            XCTAssertEqual(remote.createConversationCallCount, 0)
        } catch {
            XCTFail("非预期错误：\(error)")
        }
    }

    func testInvalidRemoteThreadDoesNotReturnThreadID() async {
        let agentID = UUID()
        let hospitalID = UUID()
        let threadID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.runtimeConfigResult = .success(HospitalCareTestFixtures.runtimeConfigDTO(
            agentID: agentID, hospitalID: hospitalID, memberID: memberID
        ))
        var conversation = HospitalConversationDTO(
            threadId: threadID,
            agent: HospitalConversationAgentDTO(id: agentID, name: "智能体", publicationStatus: "published"),
            memberId: memberID,
            hospital: HospitalCareTestFixtures.hospitalDTO(id: hospitalID)
        )
        conversation.bindingId = 130
        conversation.bindingVersion = 1788503258
        remote.createConversationResult = .success(HospitalCreateConversationResponseDTO(
            threadId: threadID,
            thread: HospitalCareTestFixtures.remoteThreadDTO(
                threadID: threadID,
                memberID: memberID,
                scenario: "not-a-scenario"
            ),
            conversation: conversation,
            initialMessages: [HospitalCareTestFixtures.remoteSystemMessageDTO(threadID: threadID)]
        ))
        let (useCase, scopeStore, _, _, stateStore) = makeUseCase(remote: remote)

        do {
            _ = try await useCase.execute(
                agentID: agentID, memberID: memberID, hospitalID: hospitalID,
                accountID: accountID, recentThreadID: nil
            )
            XCTFail("Thread 映射失败必须抛错")
        } catch let error as HospitalConversationResolveError {
            XCTAssertEqual(error, .threadMappingFailed)
        } catch {
            XCTFail("非预期错误：\(error)")
        }
        XCTAssertNil(scopeStore.scope(for: threadID, accountID: accountID))
        XCTAssertNil(stateStore.takeHospitalInitialMessages(for: threadID))
    }

    func testThreadUpsertFailureDoesNotReturnThreadID() async {
        let agentID = UUID()
        let hospitalID = UUID()
        let threadID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.runtimeConfigResult = .success(HospitalCareTestFixtures.runtimeConfigDTO(
            agentID: agentID, hospitalID: hospitalID, memberID: memberID
        ))
        remote.createConversationResult = .success(createdResponse(
            threadID: threadID, agentID: agentID, hospitalID: hospitalID, memberID: memberID
        ))
        let repository = RecordingChatRepository()
        await repository.setFailUpsertRemoteThreads(true)
        let (useCase, scopeStore, _, _, stateStore) = makeUseCase(remote: remote, repository: repository)

        do {
            _ = try await useCase.execute(
                agentID: agentID, memberID: memberID, hospitalID: hospitalID,
                accountID: accountID, recentThreadID: nil
            )
            XCTFail("Thread upsert 失败必须抛错")
        } catch let error as HospitalConversationResolveError {
            XCTAssertEqual(error, .threadMappingFailed)
        } catch {
            XCTFail("非预期错误：\(error)")
        }
        XCTAssertNil(scopeStore.scope(for: threadID, accountID: accountID))
        XCTAssertNil(stateStore.takeHospitalInitialMessages(for: threadID))
    }

    func testLegacySnapshotWithoutThreadDoesNotRegisterHospitalContext() async throws {
        let agentID = UUID()
        let hospitalID = UUID()
        let threadID = UUID()
        let remote = StubHospitalCareRemoteAPI()
        remote.runtimeConfigResult = .success(HospitalCareTestFixtures.runtimeConfigDTO(
            agentID: agentID, hospitalID: hospitalID, memberID: memberID
        ))
        var conversation = HospitalConversationDTO(
            threadId: threadID,
            agent: HospitalConversationAgentDTO(id: agentID, name: "智能体", publicationStatus: "published"),
            memberId: memberID,
            hospital: HospitalCareTestFixtures.hospitalDTO(id: hospitalID)
        )
        conversation.bindingId = 130
        conversation.bindingVersion = 1788503258
        remote.createConversationResult = .success(HospitalCreateConversationResponseDTO(
            threadId: threadID,
            thread: nil,
            conversation: conversation,
            initialMessages: []
        ))
        let (useCase, scopeStore, _, repository, stateStore) = makeUseCase(remote: remote)

        let created = try await useCase.execute(
            agentID: agentID, memberID: memberID, hospitalID: hospitalID,
            accountID: accountID, recentThreadID: nil
        )

        XCTAssertEqual(created, threadID)
        XCTAssertEqual(scopeStore.scope(for: threadID, accountID: accountID)?.agentID, agentID)
        let upserted = await repository.upsertedThreads
        XCTAssertTrue(upserted.isEmpty)
        XCTAssertNil(stateStore.takeHospitalInitialMessages(for: threadID))
    }
}
#endif
