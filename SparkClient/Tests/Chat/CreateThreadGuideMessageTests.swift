#if canImport(XCTest)
import Foundation
import XCTest

/// 新会话首条 system 引导消息插入测试：
/// - execute 后第一条消息存在且唯一（role=system、block kind=chatGuideCard、deliveryState=pending）
/// - thread 已有引导消息时幂等跳过
/// - builder 为 nil 时不插入
final class CreateThreadGuideMessageTests: XCTestCase {
    private var repository: RecordingGuideRepository!
    private var useCase: CreateThreadUseCase!

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
            guideCardBuilder: ChatGuideCardPayloadBuilder(
                healthReader: StubGuideHealthReader(),
                medicalReader: StubGuideMedicalReader(),
                logger: ConsoleLogger()
            ),
            logger: ConsoleLogger()
        )
    }

    func testExecuteInsertsExactlyOnePendingSystemGuideMessage() async throws {
        let thread = await useCase.execute(memberID: 7, title: "健康咨询")

        let messages = await repository.messages(for: thread.id)
        XCTAssertEqual(messages.count, 1)

        let guide = try XCTUnwrap(messages.first)
        XCTAssertEqual(guide.role, .system)
        XCTAssertEqual(guide.deliveryState, .pending)
        XCTAssertEqual(guide.blocks.count, 1)
        XCTAssertEqual(guide.blocks.first?.kind, .chatGuideCard)
        if case .chatGuideCard(let payload) = guide.blocks.first?.payload {
            XCTAssertEqual(payload.memberID, 7)
            XCTAssertEqual(payload.questions.count, 3)
        } else {
            XCTFail("Expected chatGuideCard block")
        }
    }

    func testExecuteSkipsGuideWhenThreadAlreadyHasOne() async throws {
        // 模拟远端同步已回填引导消息：createThread 返回前预置一条
        let prefilledRepository = PrefilledGuideRepository(
            presetPayload: ChatGuideCardPreviewFixtures.emptyPayload
        )
        let useCaseWithPrefilledThread = CreateThreadUseCase(
            repository: prefilledRepository,
            aiConfigCenter: AIConfigCenter(
                repository: StubAISettingsRepository(),
                runtimeStore: AIRuntimeStore(),
                runtimeConfigStore: AIRuntimeConfigStore()
            ),
            guideCardBuilder: ChatGuideCardPayloadBuilder(
                healthReader: StubGuideHealthReader(),
                medicalReader: StubGuideMedicalReader(),
                logger: ConsoleLogger()
            ),
            logger: ConsoleLogger()
        )

        let thread = await useCaseWithPrefilledThread.execute(memberID: nil, title: "健康咨询")
        let messages = await prefilledRepository.messages(for: thread.id)
        XCTAssertEqual(messages.count, 1, "已有引导消息时不得再插入第二条")
    }

    func testExecuteSkipsGuideWhenBuilderIsNil() async {
        let configCenter = AIConfigCenter(
            repository: StubAISettingsRepository(),
            runtimeStore: AIRuntimeStore(),
            runtimeConfigStore: AIRuntimeConfigStore()
        )
        let nilBuilderUseCase = CreateThreadUseCase(
            repository: repository,
            aiConfigCenter: configCenter,
            guideCardBuilder: nil,
            logger: ConsoleLogger()
        )

        let thread = await nilBuilderUseCase.execute(memberID: nil, title: "健康咨询")
        let messages = await repository.messages(for: thread.id)
        XCTAssertTrue(messages.isEmpty)
    }
}

// MARK: - 测试替身

private actor RecordingGuideRepository: ChatRepository {
    private var threadMessages: [UUID: [ChatMessage]] = [:]

    func messages(for threadID: UUID) -> [ChatMessage] {
        threadMessages[threadID] ?? []
    }

    func loadActiveThread() async -> ChatThread? { nil }
    func loadThread(id: UUID) async -> ChatThread? { nil }
    func loadThreads() async -> [ChatThread] { [] }
    func loadThreadListItems() async -> [ChatThreadListItem] { [] }
    func loadThreadListItem(threadID: UUID) async -> ChatThreadListItem? { nil }
    func createThread(memberID: Int?, title: String, imageDeliveryModeRaw: String?, rolePrompt: String) async -> ChatThread {
        ChatThread(memberID: memberID, title: title)
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

/// createThread 时预置一条已存在的引导消息，模拟远端同步回填后的幂等场景。
private actor PrefilledGuideRepository: ChatRepository {
    let presetPayload: ChatGuideCardPayload
    private var threadMessages: [UUID: [ChatMessage]] = [:]

    init(presetPayload: ChatGuideCardPayload) {
        self.presetPayload = presetPayload
    }

    func messages(for threadID: UUID) -> [ChatMessage] {
        threadMessages[threadID] ?? []
    }

    func loadActiveThread() async -> ChatThread? { nil }
    func loadThread(id: UUID) async -> ChatThread? { nil }
    func loadThreads() async -> [ChatThread] { [] }
    func loadThreadListItems() async -> [ChatThreadListItem] { [] }
    func loadThreadListItem(threadID: UUID) async -> ChatThreadListItem? { nil }
    func createThread(memberID: Int?, title: String, imageDeliveryModeRaw: String?, rolePrompt: String) async -> ChatThread {
        let thread = ChatThread(memberID: memberID, title: title)
        threadMessages[thread.id] = [
            ChatGuideSystemMessageFactory.make(threadID: thread.id, payload: presetPayload)
        ]
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
