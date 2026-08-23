#if canImport(XCTest)
import Foundation
import XCTest

/// CHAT-000029 新建对话流程测试：
/// - CreateThreadUseCase 只做本地 thread 创建（memberID 透传、不插入 guide 消息）；
/// - EnsureChatGuideSystemMessageUseCase 进入会话页面后幂等插入首条 system 引导卡片
///   （有成员 generating 空问题；无成员 preset 固定问题；已有卡片不重复插入）。
final class CreateThreadGuideMessageTests: XCTestCase {
    private var repository: RecordingGuideRepository!
    private var useCase: CreateThreadUseCase!
    private var ensureUseCase: EnsureChatGuideSystemMessageUseCase!

    override func setUp() async throws {
        let configCenter = AIConfigCenter(
            repository: StubAISettingsRepository(),
            runtimeStore: AIRuntimeStore(),
            runtimeConfigStore: AIRuntimeConfigStore()
        )
        repository = RecordingGuideRepository()
        useCase = CreateThreadUseCase(
            repository: repository,
            aiConfigCenter: configCenter,
            logger: ConsoleLogger()
        )
        ensureUseCase = EnsureChatGuideSystemMessageUseCase(
            repository: repository,
            guideCardBuilder: ChatGuideCardPayloadBuilder(
                healthReader: StubGuideHealthReader(),
                medicalReader: StubGuideMedicalReader(),
                logger: ConsoleLogger()
            ),
            logger: ConsoleLogger()
        )
    }

    // MARK: - CreateThreadUseCase：纯 thread 创建

    func testCreateThreadWritesInitialMemberIDWithoutGuideMessages() async throws {
        let thread = try await XCTUnwrap(
            await repository.createThreadVia(useCase, memberID: 7, title: "健康咨询")
        )
        XCTAssertEqual(thread.memberID, 7)

        // guide card 改由进入会话页面后插入，创建阶段不产生消息
        let messages = await repository.messages(for: thread.id)
        XCTAssertTrue(messages.isEmpty)
    }

    func testCreateThreadPassesNilMemberIDWhenUnbound() async throws {
        let thread = try await XCTUnwrap(
            await repository.createThreadVia(useCase, memberID: nil, title: "健康咨询")
        )
        XCTAssertNil(thread.memberID)
    }

    // MARK: - EnsureChatGuideSystemMessageUseCase：进入页面后幂等插入

    func testEnsureInsertsGeneratingGuideCardForBoundMember() async throws {
        let threadID = UUID()
        await repository.seedThread(ChatThread(id: threadID, memberID: 7, title: "健康咨询"))

        let output = await ensureUseCase.execute(threadID: threadID)
        XCTAssertTrue(output.didInsert)

        let messages = await repository.messages(for: threadID)
        XCTAssertEqual(messages.count, 1)

        let guide = try XCTUnwrap(messages.first)
        XCTAssertEqual(guide.role, .system)
        XCTAssertEqual(guide.deliveryState, .pending)
        XCTAssertEqual(guide.blocks.count, 1)
        XCTAssertEqual(guide.blocks.first?.kind, .chatGuideCard)

        let target = try XCTUnwrap(output.target)
        XCTAssertEqual(target.message.clientMessageID, guide.clientMessageID)
        XCTAssertEqual(target.payload.memberId, 7)
        XCTAssertEqual(target.payload.questions.isEmpty, true)
        XCTAssertEqual(target.payload.effectiveQuestionGenerationState, .generating)
        XCTAssertEqual(target.payload.questionGeneration?.memberId, 7)
    }

    func testEnsureInsertsPresetGuideCardWithoutMember() async throws {
        let threadID = UUID()
        await repository.seedThread(ChatThread(id: threadID, memberID: nil, title: "健康咨询"))

        let output = await ensureUseCase.execute(threadID: threadID)
        XCTAssertTrue(output.didInsert)

        let target = try XCTUnwrap(output.target)
        XCTAssertEqual(target.payload.questions, ChatGuideQuestionPreset.phaseOne)
        XCTAssertEqual(target.payload.effectiveQuestionGenerationState, .preset)
        XCTAssertEqual(target.payload.questionGeneration?.source, "preset")
    }

    func testEnsureIsIdempotentWhenGuideCardAlreadyExists() async throws {
        // 模拟远端同步已回填引导消息：不重复插入
        let prefilledRepository = PrefilledGuideRepository(
            presetPayload: ChatGuideCardPreviewFixtures.emptyPayload
        )
        let prefilledEnsureUseCase = EnsureChatGuideSystemMessageUseCase(
            repository: prefilledRepository,
            guideCardBuilder: ChatGuideCardPayloadBuilder(
                healthReader: StubGuideHealthReader(),
                medicalReader: StubGuideMedicalReader(),
                logger: ConsoleLogger()
            ),
            logger: ConsoleLogger()
        )
        let threadID = UUID()
        await prefilledRepository.seedThread(ChatThread(id: threadID, memberID: nil, title: "健康咨询"))

        let output = await prefilledEnsureUseCase.execute(threadID: threadID)
        XCTAssertFalse(output.didInsert, "已有引导消息时不得再插入第二条")
        XCTAssertNotNil(output.target, "已有引导消息时应返回现有 target")

        let messages = await prefilledRepository.messages(for: threadID)
        XCTAssertEqual(messages.count, 1)
    }

    func testEnsureSkipsWhenBuilderIsNil() async throws {
        let nilBuilderUseCase = EnsureChatGuideSystemMessageUseCase(
            repository: repository,
            guideCardBuilder: nil,
            logger: ConsoleLogger()
        )
        let threadID = UUID()
        await repository.seedThread(ChatThread(id: threadID, memberID: 7, title: "健康咨询"))

        let output = await nilBuilderUseCase.execute(threadID: threadID)
        XCTAssertNil(output.target)
        XCTAssertFalse(output.didInsert)

        let messages = await repository.messages(for: threadID)
        XCTAssertTrue(messages.isEmpty)
    }

    func testEnsureReturnsNilWhenThreadMissing() async {
        let output = await ensureUseCase.execute(threadID: UUID())
        XCTAssertNil(output.target)
        XCTAssertFalse(output.didInsert)
    }
}

// MARK: - 测试替身

private actor RecordingGuideRepository: ChatRepository {
    private var threadByID: [UUID: ChatThread] = [:]
    private var threadMessages: [UUID: [ChatMessage]] = [:]

    func messages(for threadID: UUID) -> [ChatMessage] {
        threadMessages[threadID] ?? []
    }

    func seedThread(_ thread: ChatThread) {
        threadByID[thread.id] = thread
    }

    /// 通过被测 CreateThreadUseCase 创建 thread（同时记录返回值），便于断言初始 memberID。
    func createThreadVia(_ useCase: CreateThreadUseCase, memberID: Int?, title: String) async -> ChatThread? {
        let thread = await useCase.execute(memberID: memberID, title: title)
        threadByID[thread.id] = thread
        return thread
    }

    func loadActiveThread() async -> ChatThread? { nil }
    func loadThread(id: UUID) async -> ChatThread? { threadByID[id] }
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

    func loadMessages(threadID: UUID, limit: Int?, before: Date?) async -> [ChatMessage] {
        threadMessages[threadID] ?? []
    }
    func loadMessages(clientMessageIDs: [UUID]) async -> [ChatMessage] { [] }
    func loadUsageSummary(clientMessageID: UUID) async -> ChatMessageUsageSummary? { nil }
    func countMessages(threadID: UUID) async -> Int { 0 }
    func latestServerActivity(for threadID: UUID) async -> Date? { nil }
    func appendMessage(_ message: ChatMessage) async throws -> ChatMessage {
        threadMessages[message.threadID, default: []].append(message)
        return message
    }
    func upsertLocalMessage(_ message: ChatMessage) async throws -> ChatMessage { message }
    func softDeleteMessage(clientMessageID: UUID) async {}
    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState, notifyUI: Bool) async {}
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
    func upsertRemoteThreads(_ threads: [ChatThread]) async {}
    func loadPendingAttachmentDownloadJobs(limit: Int) async -> [ChatAttachmentDownloadJobRecord] { [] }
    func updateAttachmentDownloadJob(
        id: UUID,
        state: ChatAttachmentDownloadJobRecord.State,
        localFileURLString: String?
    ) async {}
}

/// 已存在引导消息的仓储，模拟远端同步回填后的幂等场景。
private actor PrefilledGuideRepository: ChatRepository {
    let presetPayload: ChatGuideCardPayload
    private var threadByID: [UUID: ChatThread] = [:]
    private var threadMessages: [UUID: [ChatMessage]] = [:]

    init(presetPayload: ChatGuideCardPayload) {
        self.presetPayload = presetPayload
    }

    func messages(for threadID: UUID) -> [ChatMessage] {
        threadMessages[threadID] ?? []
    }

    func seedThread(_ thread: ChatThread) {
        threadByID[thread.id] = thread
        threadMessages[thread.id] = [
            ChatGuideSystemMessageFactory.make(threadID: thread.id, payload: presetPayload)
        ]
    }

    func loadActiveThread() async -> ChatThread? { nil }
    func loadThread(id: UUID) async -> ChatThread? { threadByID[id] }
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

    func loadMessages(threadID: UUID, limit: Int?, before: Date?) async -> [ChatMessage] {
        threadMessages[threadID] ?? []
    }
    func loadMessages(clientMessageIDs: [UUID]) async -> [ChatMessage] { [] }
    func loadUsageSummary(clientMessageID: UUID) async -> ChatMessageUsageSummary? { nil }
    func countMessages(threadID: UUID) async -> Int { 0 }
    func latestServerActivity(for threadID: UUID) async -> Date? { nil }
    func appendMessage(_ message: ChatMessage) async throws -> ChatMessage {
        threadMessages[message.threadID, default: []].append(message)
        return message
    }
    func upsertLocalMessage(_ message: ChatMessage) async throws -> ChatMessage { message }
    func softDeleteMessage(clientMessageID: UUID) async {}
    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState, notifyUI: Bool) async {}
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
    func upsertRemoteThreads(_ threads: [ChatThread]) async {}
    func loadPendingAttachmentDownloadJobs(limit: Int) async -> [ChatAttachmentDownloadJobRecord] { [] }
    func updateAttachmentDownloadJob(
        id: UUID,
        state: ChatAttachmentDownloadJobRecord.State,
        localFileURLString: String?
    ) async {}
}

private struct StubAISettingsRepository: AISettingsRepository {
    func loadSnapshot(ownerAccountID: Int64?) async -> AISettingsSnapshot { .default }
    func save(snapshot: AISettingsSnapshot, ownerAccountID: Int64?) async throws {}
    func saveModel(_ model: AllModels) async throws {}
    func saveScenarioBinding(_ binding: AIScenarioModelBinding, ownerAccountID: Int64?) async throws {}
    func deleteScenarioBinding(id: UUID, ownerAccountID: Int64?) async throws {}
    func saveProvider(_ provider: APIKeys) async throws {}
    func saveSearchKey(_ searchKey: SearchKeys, ownerAccountID: Int64?) async throws {}
    func deleteSearchKeys(ids: [UUID], ownerAccountID: Int64?) async throws {}
    func saveSearchToolPreferences(
        _ preferences: AISearchToolPreferences,
        revision: SearchRuntimeConfigRevision,
        searchKeys: [SearchKeys]?,
        ownerAccountID: Int64?
    ) async throws {}
    func savePromptRepo(_ promptRepo: [PromptRepo], ownerAccountID: Int64?) async throws {}
}
#endif
