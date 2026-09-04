#if canImport(XCTest)
import Foundation
@testable import SparkClient

/// CHAT-000054：HospitalCareRemoteServing 的可配置测试替身。
final class StubHospitalCareRemoteAPI: HospitalCareRemoteServing, @unchecked Sendable {
    enum StubError: Error {
        case network
    }

    var hospitalsResult: Result<[HospitalPublicDTO], Error> = .success([])
    var departmentsResult: Result<[HospitalDepartmentPublicDTO], Error> = .success([])
    var agentsResult: Result<[HospitalAgentPublicDTO], Error> = .success([])
    var agentDetailResult: Result<HospitalAgentPublicDTO, Error> = .failure(StubError.network)
    var conversationsResult: Result<[HospitalConversationDTO], Error> = .success([])
    var allConversationsResult: Result<[HospitalConversationDTO], Error> = .success([])
    var contextResult: Result<HospitalConversationContextDTO?, Error> = .success(nil)
    var createConversationResult: Result<HospitalCreateConversationResponseDTO, Error>?
    /// CHAT-000058：专用运行配置结果（nil 时抛 network）。
    var runtimeConfigResult: Result<HospitalAgentRuntimeConfigDTO, Error>?
    /// CHAT-000055：KB pull 分页队列（按调用顺序出队；用尽后返回空页）。
    var pullPages: [Result<HospitalKnowledgePullPageDTO, Error>] = []

    private(set) var fetchContextCallCount = 0
    private(set) var listAllConversationsCallCount = 0
    private(set) var pullCallCount = 0
    private(set) var pullCursors: [String?] = []
    private(set) var createConversationCallCount = 0
    private(set) var fetchRuntimeConfigCallCount = 0

    func listHospitals(page: Int, pageSize: Int) async throws -> [HospitalPublicDTO] {
        try hospitalsResult.get()
    }

    func listDepartments(hospitalID: UUID) async throws -> [HospitalDepartmentPublicDTO] {
        try departmentsResult.get()
    }

    func listAgents(
        hospitalID: UUID,
        departmentID: UUID?,
        keyword: String,
        page: Int,
        pageSize: Int
    ) async throws -> [HospitalAgentPublicDTO] {
        try agentsResult.get()
    }

    func fetchAgent(agentID: UUID) async throws -> HospitalAgentPublicDTO {
        try agentDetailResult.get()
    }

    func listConversations(memberID: Int, page: Int, pageSize: Int) async throws -> [HospitalConversationDTO] {
        try conversationsResult.get()
    }

    func listAllConversations(pageSize: Int) async throws -> [HospitalConversationDTO] {
        listAllConversationsCallCount += 1
        return try allConversationsResult.get()
    }

    func createConversation(agentID: UUID, memberID: Int) async throws -> HospitalCreateConversationResponseDTO {
        createConversationCallCount += 1
        guard let createConversationResult else {
            throw StubError.network
        }
        return try createConversationResult.get()
    }

    func fetchAgentRuntimeConfig(agentID: UUID, memberID: Int) async throws -> HospitalAgentRuntimeConfigDTO {
        fetchRuntimeConfigCallCount += 1
        guard let runtimeConfigResult else {
            throw StubError.network
        }
        return try runtimeConfigResult.get()
    }

    func fetchConversationContext(threadID: UUID, memberID: Int?) async throws -> HospitalConversationContextDTO? {
        fetchContextCallCount += 1
        return try contextResult.get()
    }

    func pullHospitalKnowledge(
        knowledgeBaseID: UUID,
        cursor: String?,
        limit: Int
    ) async throws -> HospitalKnowledgePullPageDTO {
        pullCallCount += 1
        pullCursors.append(cursor)
        if pullPages.isEmpty == false {
            return try pullPages.removeFirst().get()
        }
        return HospitalKnowledgePullPageDTO(
            knowledgeBaseId: knowledgeBaseID,
            revision: 0,
            vectorStatus: "not_built",
            indexedRevision: nil,
            cursor: nil,
            hasMore: false,
            documents: []
        )
    }
}

enum HospitalCareTestFixtures {
    static func hospitalDTO(
        id: UUID = UUID(),
        code: String? = nil,
        name: String = "测试医院",
        introduction: String? = nil
    ) -> HospitalPublicDTO {
        HospitalPublicDTO(
            id: id,
            code: code,
            name: name,
            shortName: nil,
            introduction: introduction,
            status: "active"
        )
    }

    static func hospitalSummary(
        id: UUID = UUID(),
        code: String = "",
        name: String = "测试医院",
        introduction: String = ""
    ) -> HospitalSummary {
        HospitalSummary(
            id: id,
            code: code,
            name: name,
            shortName: "",
            introduction: introduction,
            status: "active"
        )
    }

    static func agentDTO(
        id: UUID = UUID(),
        hospitalID: UUID = UUID(),
        doctorID: UUID = UUID(),
        doctorName: String = "李医生",
        publishedAt: Date? = nil,
        doctorAvatarUrl: String? = nil,
        agentAvatarUrl: String? = nil,
        agentAvatarVersion: String? = nil
    ) -> HospitalAgentPublicDTO {
        HospitalAgentPublicDTO(
            id: id,
            hospitalId: hospitalID,
            name: "\(doctorName)智能体",
            publicSummary: nil,
            greeting: nil,
            serviceBoundary: nil,
            publicationStatus: "published",
            publishedAt: publishedAt,
            department: nil,
            doctor: HospitalDoctorPublicDTO(
                id: doctorID,
                displayName: doctorName,
                title: "主任医师",
                specialties: nil,
                introduction: nil,
                avatarUrl: doctorAvatarUrl
            ),
            avatarSource: agentAvatarUrl == nil ? nil : "custom",
            avatarUrl: agentAvatarUrl,
            avatarVersion: agentAvatarVersion
        )
    }

    static func conversationDTO(
        threadID: UUID = UUID(),
        agentID: UUID = UUID(),
        memberID: Int? = 7,
        hospitalID: UUID? = UUID()
    ) -> HospitalConversationDTO {
        HospitalConversationDTO(
            threadId: threadID,
            agent: HospitalConversationAgentDTO(id: agentID, name: "智能体", publicationStatus: "published"),
            memberId: memberID,
            hospital: hospitalID.map { hospitalDTO(id: $0) }
        )
    }

    static func contextDTO(
        threadID: UUID = UUID(),
        agentID: UUID = UUID(),
        memberID: Int? = 7,
        hospitalID: UUID = UUID()
    ) -> HospitalConversationContextDTO {
        HospitalConversationContextDTO(
            threadId: threadID,
            hospital: hospitalDTO(id: hospitalID),
            agent: HospitalConversationAgentDTO(id: agentID, name: "智能体", publicationStatus: "published"),
            memberId: memberID,
            capabilities: nil,
            knowledgeManifest: nil,
            serviceStatus: nil
        )
    }

    /// CHAT-000058：医院专用模型行（字段与 Pro bootstrap chat.models 行一致）。
    static func hospitalModelRow(
        name: String = "hospital-agent-model",
        endpoint: String = "https://model.example.com/v1",
        apiKey: String? = "test-key",
        baseModelName: String? = "qwen-base"
    ) -> AIScenarioRemoteModelRow {
        AIScenarioRemoteModelRow(
            name: name,
            displayName: "李医生智能体",
            identity: "agent",
            company: "QWEN",
            endpoint: endpoint,
            apiKey: apiKey,
            supportsSearch: false,
            supportsMultimodal: false,
            supportsReasoning: false,
            supportsToolUse: false,
            supportsVoiceGen: false,
            supportsImageGen: false,
            supportsText: true,
            supportsDeepReasoning: false,
            reasoningControllable: false,
            priceTier: 0,
            systemProvision: "你是医院医生智能体",
            icon: nil,
            briefDescription: nil,
            source: "hospital",
            aiScenarios: ["chat"],
            aiToolScenarios: [],
            relatedTaskCodes: [],
            isDefault: false,
            temperature: 0.3,
            maxTokens: 2048,
            baseModelName: baseModelName
        )
    }

    /// CHAT-000058：专用运行配置 DTO。
    static func runtimeConfigDTO(
        agentID: UUID = UUID(),
        hospitalID: UUID = UUID(),
        memberID: Int = 7,
        bindingID: Int = 130,
        bindingVersion: Int = 1788503258,
        modelRow: AIScenarioRemoteModelRow = hospitalModelRow()
    ) -> HospitalAgentRuntimeConfigDTO {
        HospitalAgentRuntimeConfigDTO(
            agentId: agentID,
            hospitalId: hospitalID,
            memberId: memberID,
            doctor: HospitalAgentRuntimeDoctorDTO(
                doctorId: UUID(),
                name: "李医生",
                title: "主任医师",
                departmentName: "心内科",
                avatarUrl: nil
            ),
            profile: HospitalAgentRuntimeProfileDTO(
                name: "李医生智能体",
                description: "健康信息与就医指导",
                status: "published",
                profileVersion: 4
            ),
            runtime: HospitalAgentRuntimeDTO(
                bindingId: bindingID,
                bindingVersion: bindingVersion,
                configVersion: "\(bindingID):\(bindingVersion)",
                streaming: true,
                model: modelRow
            )
        )
    }

    /// CHAT-000058：领域配置（与 runtimeConfigDTO 默认值对齐）。
    static func runtimeConfig(
        agentID: UUID = UUID(),
        hospitalID: UUID = UUID(),
        memberID: Int = 7,
        bindingID: Int = 130,
        bindingVersion: Int = 1788503258
    ) -> HospitalAgentRuntimeConfig {
        HospitalAgentRuntimeConfig(
            agentID: agentID,
            hospitalID: hospitalID,
            memberID: memberID,
            doctorName: "李医生",
            doctorTitle: "主任医师",
            departmentName: "心内科",
            doctorAvatarURL: nil,
            profileName: "李医生智能体",
            profileVersion: 4,
            bindingID: bindingID,
            bindingVersion: bindingVersion,
            configVersion: "\(bindingID):\(bindingVersion)",
            streaming: true,
            modelRow: hospitalModelRow()
        )
    }
}

/// CHAT-000058：内存版 Keychain 替身（不触碰真实 Keychain）。
final class InMemoryHospitalAgentRuntimeConfigKeychain: HospitalAgentRuntimeConfigKeychainServing, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private(set) var deletedAccounts: [String] = []

    func save(_ data: Data, account: String) throws {
        lock.lock()
        storage[account] = data
        lock.unlock()
    }

    func load(account: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[account]
    }

    func delete(account: String) {
        lock.lock()
        storage[account] = nil
        deletedAccounts.append(account)
        lock.unlock()
    }
}
#endif
