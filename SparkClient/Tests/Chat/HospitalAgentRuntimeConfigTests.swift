#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

/// CHAT-000058：专用运行配置 DTO 解码、DTO→领域映射与 Keychain/内存存取隔离。
final class HospitalAgentRuntimeConfigTests: XCTestCase {
    private let accountID: Int64 = 42

    private func makeStore(
        keychain: InMemoryHospitalAgentRuntimeConfigKeychain = InMemoryHospitalAgentRuntimeConfigKeychain(),
        defaults: UserDefaults? = nil
    ) -> HospitalAgentRuntimeConfigStore {
        let suite = "HospitalAgentRuntimeConfigTests.\(UUID().uuidString)"
        return HospitalAgentRuntimeConfigStore(
            keychain: keychain,
            defaults: defaults ?? UserDefaults(suiteName: suite)!
        )
    }

    private func scope(
        agentID: UUID,
        hospitalID: UUID,
        memberID: Int
    ) -> HospitalAgentRuntimeConfigStore.Scope {
        HospitalAgentRuntimeConfigStore.Scope(
            accountID: accountID,
            hospitalID: hospitalID,
            memberID: memberID,
            agentID: agentID
        )
    }

    // MARK: - DTO 解码（与服务端契约字段一致）

    func testRuntimeConfigDTODecodesServerJSON() throws {
        let agentID = UUID()
        let hospitalID = UUID()
        let doctorID = UUID()
        let json = """
        {
          "agent_id": "\(agentID.uuidString.lowercased())",
          "hospital_id": "\(hospitalID.uuidString.lowercased())",
          "member_id": 123,
          "doctor": {
            "doctor_id": "\(doctorID.uuidString.lowercased())",
            "name": "张医生",
            "title": "主任医师",
            "department_name": "心内科",
            "avatar_url": "https://cdn.example.com/avatar.png"
          },
          "profile": {
            "name": "张医生智能体",
            "description": "健康信息与就医指导",
            "status": "published",
            "profile_version": 4
          },
          "runtime": {
            "binding_id": 130,
            "binding_version": 1788503258,
            "config_version": "130:1788503258",
            "streaming": true,
            "model": {
              "name": "hospital-agent-model",
              "display_name": "张医生智能体",
              "identity": "agent",
              "baseModelName": "qwen-base",
              "company": "QWEN",
              "endpoint": "https://model.example.com/v1",
              "api_key": "test-key",
              "supports_search": false,
              "supports_multimodal": true,
              "supports_reasoning": false,
              "supports_tool_use": false,
              "supports_voice_gen": false,
              "supports_image_gen": false,
              "supports_text": true,
              "supports_deep_reasoning": false,
              "reasoning_controllable": false,
              "price_tier": 0,
              "systemProvision": "你是医院医生智能体",
              "icon": null,
              "briefDescription": null,
              "source": "hospital",
              "aiScenarios": ["chat"],
              "aiToolScenarios": [],
              "relatedTaskCodes": [],
              "is_default": false,
              "temperature": 0.3,
              "max_tokens": 2048
            }
          }
        }
        """
        let dto = try JSONDecoder.chatRemote.decode(
            HospitalAgentRuntimeConfigDTO.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(dto.agentId, agentID)
        XCTAssertEqual(dto.hospitalId, hospitalID)
        XCTAssertEqual(dto.memberId, 123)
        XCTAssertEqual(dto.doctor.doctorId, doctorID)
        XCTAssertEqual(dto.doctor.name, "张医生")
        XCTAssertEqual(dto.doctor.departmentName, "心内科")
        XCTAssertEqual(dto.profile.profileVersion, 4)
        XCTAssertEqual(dto.runtime.bindingId, 130)
        XCTAssertEqual(dto.runtime.bindingVersion, 1788503258)
        XCTAssertEqual(dto.runtime.configVersion, "130:1788503258")
        XCTAssertEqual(dto.runtime.streaming, true)
        XCTAssertEqual(dto.runtime.model.name, "hospital-agent-model")
        XCTAssertEqual(dto.runtime.model.displayName, "张医生智能体")
        XCTAssertEqual(dto.runtime.model.identity, "agent")
        XCTAssertEqual(dto.runtime.model.baseModelName, "qwen-base")
        XCTAssertEqual(dto.runtime.model.apiKey, "test-key")
        XCTAssertEqual(dto.runtime.model.supportsMultimodal, true)
        XCTAssertEqual(dto.runtime.model.systemPrompt, "你是医院医生智能体")
        XCTAssertEqual(dto.runtime.model.source, "hospital")
        XCTAssertEqual(dto.runtime.model.maxTokens, 2048)
    }

    // MARK: - DTO → 领域映射（身份校验）

    func testMakeRejectsMismatchedIdentity() {
        let agentID = UUID()
        let hospitalID = UUID()
        let dto = HospitalCareTestFixtures.runtimeConfigDTO(agentID: agentID, hospitalID: hospitalID, memberID: 7)

        XCTAssertNotNil(HospitalAgentRuntimeConfig.make(
            from: dto, expectedAgentID: agentID, expectedMemberID: 7, expectedHospitalID: hospitalID
        ))
        XCTAssertNil(HospitalAgentRuntimeConfig.make(
            from: dto, expectedAgentID: UUID(), expectedMemberID: 7, expectedHospitalID: hospitalID
        ))
        XCTAssertNil(HospitalAgentRuntimeConfig.make(
            from: dto, expectedAgentID: agentID, expectedMemberID: 8, expectedHospitalID: hospitalID
        ))
        XCTAssertNil(HospitalAgentRuntimeConfig.make(
            from: dto, expectedAgentID: agentID, expectedMemberID: 7, expectedHospitalID: UUID()
        ))
    }

    // MARK: - Store：内存读写与 Keychain 索引

    func testStoreMemoryRoundTrip() {
        let keychain = InMemoryHospitalAgentRuntimeConfigKeychain()
        let store = makeStore(keychain: keychain)
        let agentID = UUID()
        let hospitalID = UUID()
        let config = HospitalCareTestFixtures.runtimeConfig(agentID: agentID, hospitalID: hospitalID, memberID: 7)

        store.save(config, accountID: accountID)

        let hit = store.cachedConfig(for: scope(agentID: agentID, hospitalID: hospitalID, memberID: 7))
        XCTAssertEqual(hit, config)
        // 不同 scope 不得命中同一配置。
        XCTAssertNil(store.cachedConfig(for: scope(agentID: UUID(), hospitalID: hospitalID, memberID: 7)))
        XCTAssertNil(store.cachedConfig(for: scope(agentID: agentID, hospitalID: hospitalID, memberID: 8)))
    }

    func testStoreLoadsFromKeychainOnColdMemory() {
        let keychain = InMemoryHospitalAgentRuntimeConfigKeychain()
        let defaults = UserDefaults(suiteName: "HospitalAgentRuntimeConfigTests.\(UUID().uuidString)")!
        let writer = makeStore(keychain: keychain, defaults: defaults)
        let agentID = UUID()
        let hospitalID = UUID()
        let config = HospitalCareTestFixtures.runtimeConfig(agentID: agentID, hospitalID: hospitalID, memberID: 7)
        writer.save(config, accountID: accountID)

        // 新实例（内存为空）应从 Keychain 恢复。
        let reader = makeStore(keychain: keychain, defaults: defaults)
        let hit = reader.cachedConfig(for: scope(agentID: agentID, hospitalID: hospitalID, memberID: 7))
        XCTAssertEqual(hit, config)
    }

    func testStoreClearMemberOnlyRemovesThatMember() {
        let keychain = InMemoryHospitalAgentRuntimeConfigKeychain()
        let defaults = UserDefaults(suiteName: "HospitalAgentRuntimeConfigTests.\(UUID().uuidString)")!
        let store = makeStore(keychain: keychain, defaults: defaults)
        let hospitalID = UUID()
        let memberSevenAgent = UUID()
        let memberEightAgent = UUID()
        store.save(HospitalCareTestFixtures.runtimeConfig(agentID: memberSevenAgent, hospitalID: hospitalID, memberID: 7), accountID: accountID)
        store.save(HospitalCareTestFixtures.runtimeConfig(agentID: memberEightAgent, hospitalID: hospitalID, memberID: 8), accountID: accountID)

        store.clearMember(accountID: accountID, memberID: 7)

        XCTAssertNil(store.cachedConfig(for: scope(agentID: memberSevenAgent, hospitalID: hospitalID, memberID: 7)))
        XCTAssertNotNil(store.cachedConfig(for: scope(agentID: memberEightAgent, hospitalID: hospitalID, memberID: 8)))
        // 冷实例同样不得恢复已清理成员（Keychain 已删除）。
        let cold = makeStore(keychain: keychain, defaults: defaults)
        XCTAssertNil(cold.cachedConfig(for: scope(agentID: memberSevenAgent, hospitalID: hospitalID, memberID: 7)))
        XCTAssertNotNil(cold.cachedConfig(for: scope(agentID: memberEightAgent, hospitalID: hospitalID, memberID: 8)))
    }

    func testStoreClearAccountRemovesEverything() {
        let keychain = InMemoryHospitalAgentRuntimeConfigKeychain()
        let defaults = UserDefaults(suiteName: "HospitalAgentRuntimeConfigTests.\(UUID().uuidString)")!
        let store = makeStore(keychain: keychain, defaults: defaults)
        let hospitalID = UUID()
        let agentID = UUID()
        store.save(HospitalCareTestFixtures.runtimeConfig(agentID: agentID, hospitalID: hospitalID, memberID: 7), accountID: accountID)

        store.clearAccount(accountID)

        let cold = makeStore(keychain: keychain, defaults: defaults)
        XCTAssertNil(cold.cachedConfig(for: scope(agentID: agentID, hospitalID: hospitalID, memberID: 7)))
    }

    func testStoreDeleteSingleScope() {
        let keychain = InMemoryHospitalAgentRuntimeConfigKeychain()
        let defaults = UserDefaults(suiteName: "HospitalAgentRuntimeConfigTests.\(UUID().uuidString)")!
        let store = makeStore(keychain: keychain, defaults: defaults)
        let hospitalID = UUID()
        let agentID = UUID()
        let target = scope(agentID: agentID, hospitalID: hospitalID, memberID: 7)
        store.save(HospitalCareTestFixtures.runtimeConfig(agentID: agentID, hospitalID: hospitalID, memberID: 7), accountID: accountID)

        store.delete(for: target)

        let cold = makeStore(keychain: keychain, defaults: defaults)
        XCTAssertNil(cold.cachedConfig(for: target))
        XCTAssertTrue(keychain.deletedAccounts.contains(target.storageKey))
    }

    // MARK: - 错误码映射

    func testFetchUseCaseMapsBusinessErrorCodes() {
        func httpError(_ status: Int, _ code: String) -> Error {
            SparkNetworkError.httpError(
                statusCode: status,
                backend: BackendError(code: 1, msg: code, data: nil),
                rawBody: Data()
            )
        }
        XCTAssertEqual(
            FetchHospitalAgentRuntimeConfigUseCase.mapError(httpError(403, "MEMBER_ACCESS_DENIED")) as? HospitalAgentRuntimeConfigError,
            .memberAccessDenied
        )
        XCTAssertEqual(
            FetchHospitalAgentRuntimeConfigUseCase.mapError(httpError(404, "AGENT_NOT_FOUND")) as? HospitalAgentRuntimeConfigError,
            .agentNotFound
        )
        XCTAssertEqual(
            FetchHospitalAgentRuntimeConfigUseCase.mapError(httpError(409, "AGENT_UNAVAILABLE")) as? HospitalAgentRuntimeConfigError,
            .agentUnavailable
        )
        XCTAssertEqual(
            FetchHospitalAgentRuntimeConfigUseCase.mapError(httpError(409, "AGENT_BINDING_INVALID")) as? HospitalAgentRuntimeConfigError,
            .bindingInvalid
        )
        XCTAssertEqual(
            FetchHospitalAgentRuntimeConfigUseCase.mapError(httpError(409, "RUNTIME_CONFIG_INVALID")) as? HospitalAgentRuntimeConfigError,
            .runtimeConfigInvalid
        )
        XCTAssertEqual(
            FetchHospitalAgentRuntimeConfigUseCase.mapError(httpError(400, "PAYLOAD_INVALID")) as? HospitalAgentRuntimeConfigError,
            .payloadInvalid
        )
        XCTAssertEqual(
            FetchHospitalAgentRuntimeConfigUseCase.mapError(httpError(401, "AUTH_REQUIRED")) as? HospitalAgentRuntimeConfigError,
            .unauthorized
        )
        XCTAssertEqual(
            FetchHospitalAgentRuntimeConfigUseCase.mapError(StubHospitalCareRemoteAPI.StubError.network) as? HospitalAgentRuntimeConfigError,
            .network
        )
    }
}
#endif
