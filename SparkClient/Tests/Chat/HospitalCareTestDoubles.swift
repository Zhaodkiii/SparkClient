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
    /// 线上问诊：提交结果（nil 时抛 network）。
    var submitConsultationResult: Result<HospitalConsultationDTO, Error>?
    var consultationsResult: Result<[HospitalConsultationDTO], Error> = .success([])

    private(set) var fetchContextCallCount = 0
    private(set) var listAllConversationsCallCount = 0
    private(set) var pullCallCount = 0
    private(set) var pullCursors: [String?] = []
    private(set) var createConversationCallCount = 0
    private(set) var fetchRuntimeConfigCallCount = 0
    private(set) var submitConsultationCallCount = 0
    private(set) var lastConsultationPayload: HospitalConsultationSubmitRequestDTO?

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

    func submitConsultation(_ payload: HospitalConsultationSubmitRequestDTO) async throws -> HospitalConsultationDTO {
        submitConsultationCallCount += 1
        lastConsultationPayload = payload
        guard let submitConsultationResult else {
            throw StubError.network
        }
        return try submitConsultationResult.get()
    }

    func listConsultations(memberID: Int?, page: Int, pageSize: Int) async throws -> [HospitalConsultationDTO] {
        try consultationsResult.get()
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
        hospitalID: UUID? = UUID(),
        consultation: HospitalConversationConsultationRefDTO? = nil
    ) -> HospitalConversationDTO {
        HospitalConversationDTO(
            threadId: threadID,
            agent: HospitalConversationAgentDTO(id: agentID, name: "智能体", publicationStatus: "published"),
            memberId: memberID,
            hospital: hospitalID.map { hospitalDTO(id: $0) },
            consultation: consultation
        )
    }

    /// 线上问诊单 fixture。
    static func consultationDTO(
        consultationID: UUID = UUID(),
        consultNo: String = "C202609050001",
        threadID: UUID = UUID(),
        agentID: UUID = UUID(),
        memberID: Int? = 7,
        hospitalID: UUID = UUID(),
        chiefComplaint: String = "最近胸口闷",
        serviceStatus: String = "pending_doctor",
        attachmentCount: Int? = 0
    ) -> HospitalConsultationDTO {
        HospitalConsultationDTO(
            consultationId: consultationID,
            consultNo: consultNo,
            threadId: threadID,
            hospital: hospitalDTO(id: hospitalID),
            department: HospitalDepartmentPublicDTO(id: UUID(), name: "心内科", sortOrder: 1),
            doctor: HospitalDoctorPublicDTO(
                id: UUID(),
                displayName: "李医生",
                title: "主任医师",
                specialties: ["心内科"],
                introduction: nil,
                avatarUrl: nil
            ),
            agent: HospitalConversationAgentDTO(id: agentID, name: "智能体", publicationStatus: "published"),
            memberId: memberID,
            chiefComplaint: chiefComplaint,
            orderItems: ["复诊开药"],
            pastHistory: "高血压三年",
            familyHistory: nil,
            allergyHistory: "青霉素过敏",
            serviceStatus: serviceStatus,
            submittedAt: Date(),
            attachmentCount: attachmentCount
        )
    }

    static func contextDTO(
        threadID: UUID = UUID(),
        agentID: UUID = UUID(),
        memberID: Int? = 7,
        hospitalID: UUID = UUID(),
        consultation: HospitalConversationConsultationRefDTO? = nil
    ) -> HospitalConversationContextDTO {
        HospitalConversationContextDTO(
            threadId: threadID,
            hospital: hospitalDTO(id: hospitalID),
            agent: HospitalConversationAgentDTO(id: agentID, name: "智能体", publicationStatus: "published"),
            memberId: memberID,
            capabilities: nil,
            knowledgeManifest: nil,
            serviceStatus: nil,
            consultation: consultation
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

/// CHAT-000060：记录 Thread upsert 的内存仓储。
actor RecordingChatRepository: ChatRepository {
    private var threadByID: [UUID: ChatThread] = [:]
    private(set) var upsertedThreads: [ChatThread] = []
    var failUpsertRemoteThreads = false

    func setFailUpsertRemoteThreads(_ value: Bool) {
        failUpsertRemoteThreads = value
    }

    func loadThread(id: UUID) async -> ChatThread? { threadByID[id] }
    func loadActiveThread() async -> ChatThread? { nil }
    func loadThreads() async -> [ChatThread] { Array(threadByID.values) }
    func loadThreadListItems() async -> [ChatThreadListItem] { [] }
    func loadThreadListItem(threadID: UUID) async -> ChatThreadListItem? { nil }
    func createThread(memberID: Int?, title: String, imageDeliveryModeRaw: String?, rolePrompt: String) async -> ChatThread {
        let thread = ChatThread(memberID: memberID, title: title)
        threadByID[thread.id] = thread
        return thread
    }
    func setActiveThread(id: UUID) async {}
    func updateThreadMemberBinding(threadID: UUID, memberID: Int?) async {}
    func updateThreadImageDeliveryMode(threadID: UUID, imageDeliveryModeRaw: String?) async {}
    func updateThreadCurrentModelName(threadID: UUID, currentModelName: String?) async {}
    func updateThreadTitle(threadID: UUID, title: String) async {}
    func updateThreadGenerationConfig(
        threadID: UUID,
        currentModelName: String?,
        temperature: Double?,
        topP: Double,
        maxTokens: Int?,
        maxMessages: Int,
        rolePrompt: String
    ) async {}
    func updateThreadAppearance(threadID: UUID, title: String, iconName: String?, iconColorName: String?) async {}
    func updateThreadPinState(threadID: UUID, isPinned: Bool, pinnedAt: Date?) async {}
    func softDeleteThread(id: UUID) async {}
    func loadPendingThreadDeletionIDs(limit: Int) async -> [UUID] { [] }
    func removePendingThreadDeletionIDs(_ ids: [UUID]) async {}
    func deleteThread(id: UUID) async {}

    func loadMessages(threadID: UUID, limit: Int?, before: Date?) async -> [ChatMessage] { [] }
    func loadMessages(clientMessageIDs: [UUID]) async -> [ChatMessage] { [] }
    func loadUsageSummary(clientMessageID: UUID) async -> ChatMessageUsageSummary? { nil }
    func countMessages(threadID: UUID) async -> Int { 0 }
    func latestServerActivity(for threadID: UUID) async -> Date? { nil }
    func appendMessage(_ message: ChatMessage) async throws -> ChatMessage { message }
    func upsertLocalMessage(_ message: ChatMessage) async throws -> ChatMessage { message }
    func softDeleteMessage(clientMessageID: UUID) async {}
    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState, notifyUI: Bool) async {}
    func markAssistantMessagesRead(threadID: UUID, upTo boundary: Date) async -> Int { 0 }
    func applyPushMessageAck(clientMessageID: UUID, serverMessageID: String?, serverUpdatedAt: Date, notifyUI: Bool) async {}
    func updateMessageBlocks(clientMessageID: UUID, blocks: [ChatMessageBlock], markPendingForSync: Bool) async {}
    func upsertMessageBlock(clientMessageID: UUID, block: ChatMessageBlock, markPendingForSync: Bool) async -> Bool { false }
    func upsertRemoteMessages(_ messages: [ChatMessage], in threadID: UUID, enqueueAttachmentDownloadJobs: Bool) async {}
    func loadOutboxMessages(limit: Int) async -> [ChatMessage] { [] }
    func loadPendingMessageBlocks(limit: Int) async -> [ChatPendingMessageBlock] { [] }
    func markMessageBlocksSynced(ids: [UUID]) async {}
    func appendUsageEvent(_ event: ChatMessageUsageEvent) async {}
    func upsertUsageSummary(_ summary: ChatMessageUsageSummary) async {}

    func loadSyncCursor() async -> ChatSyncCursor? { nil }
    func saveSyncCursor(_ cursor: ChatSyncCursor) async {}
    func loadThreadSyncCursor() async -> ChatSyncCursor? { nil }
    func saveThreadSyncCursor(_ cursor: ChatSyncCursor) async {}
    func loadMessageSyncCursor(for threadID: UUID) async -> ChatSyncCursor? { nil }
    func saveMessageSyncCursor(_ cursor: ChatSyncCursor, for threadID: UUID) async {}
    func deleteMessageSyncCursor(for threadID: UUID) async {}
    func upsertRemoteThreads(_ threads: [ChatThread]) async {
        upsertedThreads.append(contentsOf: threads)
        guard failUpsertRemoteThreads == false else { return }
        for thread in threads {
            threadByID[thread.id] = thread
        }
    }
    func loadPendingAttachmentDownloadJobs(limit: Int) async -> [ChatAttachmentDownloadJobRecord] { [] }
    func updateAttachmentDownloadJob(
        id: UUID,
        state: ChatAttachmentDownloadJobRecord.State,
        localFileURLString: String?
    ) async {}
}

extension HospitalCareTestFixtures {
    static func remoteThreadDTO(
        threadID: UUID,
        memberID: Int,
        title: String = "李医生智能体",
        scenario: String = "chat"
    ) -> ChatRemoteThreadDTO {
        ChatRemoteThreadDTO(
            threadID: threadID,
            title: title,
            scenario: scenario,
            patientID: nil,
            memberID: memberID,
            isDeleted: false,
            deletedAt: nil,
            updatedAt: Date(),
            serverUpdatedAt: Date(),
            imageDeliveryModeRaw: nil,
            currentModelName: nil,
            temperature: 1.0,
            topP: 1.0,
            maxTokens: 12048,
            maxMessages: 20,
            rolePrompt: "服务边界"
        )
    }

    static func remoteSystemMessageDTO(threadID: UUID, serverMessageID: String = "server-intro") -> ChatRemoteMessageDTO {
        ChatRemoteMessageDTO(
            threadId: threadID,
            role: "system",
            blocks: [],
            clientMessageId: UUID(),
            serverMessageId: serverMessageID,
            deliveryState: "sent",
            createdAt: Date(),
            serverUpdatedAt: Date(),
            tombstone: false,
            threadCurrentModelName: nil,
            threadTemperature: nil,
            threadTopP: nil,
            threadMaxTokens: nil,
            threadMaxMessages: nil,
            threadRolePrompt: nil,
            threadSystemPrompt: nil,
            modelName: nil,
            sender: nil
        )
    }
}
#endif
