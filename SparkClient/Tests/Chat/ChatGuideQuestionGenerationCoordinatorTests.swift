#if canImport(XCTest)
import Foundation
import XCTest

/// CHAT-000028：科普问题生成触发边界收口 + 固定兜底 + generated 回写链路测试。
@MainActor
final class ChatGuideQuestionGenerationCoordinatorTests: XCTestCase {
    // MARK: - 新建对话触发（3.3）

    func testNewThreadWithMemberStartsSingleGeneration() async {
        let threadID = UUID()
        let thread = ChatThread(id: threadID, memberID: 10, title: "Test")
        let message = ChatGuideSystemMessageFactory.make(
            threadID: threadID,
            payload: generatingPayload(memberID: 10)
        )

        let repository = GuideCoordinatorTestRepository()
        await repository.seed(thread: thread, message: message)

        let runtime = SlowGuideQuestionRuntime(delayNanoseconds: 300_000_000)
        let coordinator = makeCoordinator(repository: repository, runtime: runtime)
        let stateStore = ChatStateStore()

        await coordinator.startForNewThread(
            threadID: threadID,
            messages: [message],
            stateStore: stateStore,
            resolveModelName: { _ in nil }
        )
        // 同一新建链路重复调用：去重，不重复生成
        await coordinator.startForNewThread(
            threadID: threadID,
            messages: [message],
            stateStore: stateStore,
            resolveModelName: { _ in nil }
        )

        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(runtime.callCount, 1)
    }

    func testNewThreadWithoutMemberAppliesPresetWithoutAI() async {
        let threadID = UUID()
        let thread = ChatThread(id: threadID, memberID: nil, title: "Test")
        let message = ChatGuideSystemMessageFactory.make(
            threadID: threadID,
            payload: generatingPayload(memberID: nil)
        )

        let repository = GuideCoordinatorTestRepository()
        await repository.seed(thread: thread, message: message)

        let runtime = SlowGuideQuestionRuntime(delayNanoseconds: 100_000_000)
        let coordinator = makeCoordinator(repository: repository, runtime: runtime)
        let stateStore = ChatStateStore()

        await coordinator.startForNewThread(
            threadID: threadID,
            messages: [message],
            stateStore: stateStore,
            resolveModelName: { _ in nil }
        )

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(runtime.callCount, 0)
        let lastPayload = await repository.lastPayload
        XCTAssertEqual(lastPayload?.effectiveQuestionGenerationState, .preset)
        XCTAssertEqual(lastPayload?.questions, ChatGuideQuestionPreset.phaseOne)
    }

    // MARK: - 成员切换触发（3.3）

    func testMemberSwitchStartsNewGeneration() async {
        let threadID = UUID()
        let thread = ChatThread(id: threadID, memberID: 10, title: "Test")
        let message = ChatGuideSystemMessageFactory.make(
            threadID: threadID,
            payload: generatingPayload(memberID: 10)
        )

        let repository = GuideCoordinatorTestRepository()
        await repository.seed(thread: thread, message: message)

        let runtime = SlowGuideQuestionRuntime(delayNanoseconds: 300_000_000)
        let coordinator = makeCoordinator(repository: repository, runtime: runtime)
        let stateStore = ChatStateStore()

        await coordinator.startForNewThread(
            threadID: threadID,
            messages: [message],
            stateStore: stateStore,
            resolveModelName: { _ in nil }
        )

        await repository.updateThreadMemberID(11, for: threadID)
        // 复用原 message/block id，仅切换 payload 成员
        let sameIDMessage = message.replacingBlocks(
            message.blocks.map { block in
                guard block.kind == .chatGuideCard else { return block }
                return block.replacingPayload(.chatGuideCard(generatingPayload(memberID: 11)), status: .ready)
            }
        )
        await repository.replaceMessages([sameIDMessage], for: threadID)

        await coordinator.handleMemberBindingChanged(
            threadID: threadID,
            newMemberID: 11,
            messages: [sameIDMessage],
            stateStore: stateStore,
            resolveModelName: { _ in nil }
        )

        try? await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(runtime.callCount, 2)
        let lastPayload = await repository.lastPayload
        XCTAssertEqual(lastPayload?.effectiveQuestionGenerationState, .generated)
        XCTAssertEqual(lastPayload?.questionGeneration?.memberId, 11)
    }

    func testMemberSwitchToNilAppliesPresetWithoutAI() async {
        let threadID = UUID()
        let thread = ChatThread(id: threadID, memberID: 10, title: "Test")
        let message = ChatGuideSystemMessageFactory.make(
            threadID: threadID,
            payload: generatingPayload(memberID: 10)
        )

        let repository = GuideCoordinatorTestRepository()
        await repository.seed(thread: thread, message: message)

        let runtime = SlowGuideQuestionRuntime(delayNanoseconds: 100_000_000)
        let coordinator = makeCoordinator(repository: repository, runtime: runtime)
        let stateStore = ChatStateStore()

        await coordinator.handleMemberBindingChanged(
            threadID: threadID,
            newMemberID: nil,
            messages: [message],
            stateStore: stateStore,
            resolveModelName: { _ in nil }
        )

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(runtime.callCount, 0)
        let lastPayload = await repository.lastPayload
        XCTAssertEqual(lastPayload?.effectiveQuestionGenerationState, .preset)
        XCTAssertEqual(lastPayload?.questions, ChatGuideQuestionPreset.phaseOne)
    }

    func testStartupDefaultBindingOnOldThreadDoesNotGenerate() async {
        let threadID = UUID()
        let thread = ChatThread(id: threadID, memberID: nil, title: "Test")
        // 旧对话残留 generating 空问题卡片
        let message = ChatGuideSystemMessageFactory.make(
            threadID: threadID,
            payload: generatingPayload(memberID: nil)
        )

        let repository = GuideCoordinatorTestRepository()
        await repository.seed(thread: thread, message: message)

        let runtime = SlowGuideQuestionRuntime(delayNanoseconds: 100_000_000)
        let coordinator = makeCoordinator(repository: repository, runtime: runtime)
        let stateStore = ChatStateStore()

        await coordinator.handleMemberBindingChanged(
            threadID: threadID,
            newMemberID: 10,
            messages: [message],
            stateStore: stateStore,
            resolveModelName: { _ in nil },
            allowGeneration: false
        )

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(runtime.callCount, 0)
        let lastPayload = await repository.lastPayload
        XCTAssertEqual(lastPayload?.questions, ChatGuideQuestionPreset.phaseOne)
    }

    // MARK: - 重新进入对话策略（3.2）

    func testReenterGeneratedThreadDoesNotGenerate() async {
        try await assertReenterDoesNotGenerate(payload: generatedPayload(memberID: 10))
    }

    func testReenterFallbackThreadDoesNotGenerate() async {
        try await assertReenterDoesNotGenerate(payload: fallbackPayload(memberID: 10))
    }

    func testReenterPresetThreadDoesNotGenerate() async {
        try await assertReenterDoesNotGenerate(payload: presetPayload())
    }

    private func assertReenterDoesNotGenerate(payload: ChatGuideCardPayload) async throws {
        let threadID = UUID()
        let thread = ChatThread(id: threadID, memberID: 10, title: "Test")
        let message = ChatGuideSystemMessageFactory.make(threadID: threadID, payload: payload)

        let repository = GuideCoordinatorTestRepository()
        await repository.seed(thread: thread, message: message)

        let runtime = SlowGuideQuestionRuntime(delayNanoseconds: 100_000_000)
        let coordinator = makeCoordinator(repository: repository, runtime: runtime)
        let stateStore = ChatStateStore()

        await coordinator.repairGuideQuestionsForReenteredThread(
            threadID: threadID,
            messages: [message],
            stateStore: stateStore
        )

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(runtime.callCount, 0)
        // 已有可展示 questions：原样展示，不触发任何 block 回写
        let lastPayload = await repository.lastPayload
        XCTAssertNil(lastPayload)
    }

    func testReenterStaleGeneratingThreadRepairsToPresetWithoutAI() async {
        let threadID = UUID()
        let thread = ChatThread(id: threadID, memberID: 10, title: "Test")
        let message = ChatGuideSystemMessageFactory.make(
            threadID: threadID,
            payload: generatingPayload(memberID: 10)
        )

        let repository = GuideCoordinatorTestRepository()
        await repository.seed(thread: thread, message: message)

        let runtime = SlowGuideQuestionRuntime(delayNanoseconds: 100_000_000)
        let coordinator = makeCoordinator(repository: repository, runtime: runtime)
        let stateStore = ChatStateStore()

        await coordinator.repairGuideQuestionsForReenteredThread(
            threadID: threadID,
            messages: [message],
            stateStore: stateStore
        )

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(runtime.callCount, 0)
        let lastPayload = await repository.lastPayload
        XCTAssertEqual(lastPayload?.effectiveQuestionGenerationState, .fallback)
        XCTAssertEqual(lastPayload?.questionGeneration?.source, "preset")
        XCTAssertEqual(lastPayload?.questionGeneration?.errorMessage, "recovered_from_stale_generating")
        XCTAssertEqual(lastPayload?.questions, ChatGuideQuestionPreset.phaseOne)
    }

    // MARK: - 解码失败固定兜底（3.1）

    func testDecodeFailureAppliesPresetFallbackWithoutRepair() async {
        let threadID = UUID()
        let thread = ChatThread(id: threadID, memberID: 10, title: "Test")
        let message = ChatGuideSystemMessageFactory.make(
            threadID: threadID,
            payload: generatingPayload(memberID: 10)
        )

        let repository = GuideCoordinatorTestRepository()
        await repository.seed(thread: thread, message: message)

        // AI 返回非 JSON：直接兜底，不再发起 repair 二次请求
        let runtime = SlowGuideQuestionRuntime(delayNanoseconds: 100_000, responses: ["not-json"])
        let coordinator = makeCoordinator(repository: repository, runtime: runtime)
        let stateStore = ChatStateStore()

        await coordinator.startForNewThread(
            threadID: threadID,
            messages: [message],
            stateStore: stateStore,
            resolveModelName: { _ in nil }
        )

        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(runtime.callCount, 1)
        let lastPayload = await repository.lastPayload
        XCTAssertEqual(lastPayload?.effectiveQuestionGenerationState, .fallback)
        XCTAssertEqual(lastPayload?.questionGeneration?.source, "preset")
        XCTAssertEqual(lastPayload?.questions, ChatGuideQuestionPreset.phaseOne)
        XCTAssertTrue(lastPayload?.questionGeneration?.errorMessage?.hasPrefix("parse_failed_") == true)
    }

    // MARK: - AI 成功回写链路（3.4）

    func testGeneratedAppliesWhenPayloadMemberIDMissingForSameThreadMember() async {
        let threadID = UUID()
        let thread = ChatThread(id: threadID, memberID: 10, title: "Test")
        let message = ChatGuideSystemMessageFactory.make(
            threadID: threadID,
            payload: generatingPayload(memberID: 10)
        )

        let repository = GuideCoordinatorTestRepository()
        await repository.seed(thread: thread, message: message)

        let runtime = SlowGuideQuestionRuntime(delayNanoseconds: 400_000_000)
        let coordinator = makeCoordinator(repository: repository, runtime: runtime)
        let stateStore = ChatStateStore()

        await coordinator.startForNewThread(
            threadID: threadID,
            messages: [message],
            stateStore: stateStore,
            resolveModelName: { _ in nil }
        )

        // 模拟历史 bug 数据：生成中 payload 的 meta 缺少 memberID（同 thread 成员不变）
        try? await Task.sleep(nanoseconds: 100_000_000)
        await repository.overwriteGuidePayload(
            ChatGuideCardPayload(
                schemaVersion: 2,
                generatedAt: Date(),
                memberId: 10,
                metricSections: [],
                questions: [],
                questionGeneration: ChatGuideQuestionGenerationMeta(
                    state: .generating,
                    source: "current_chat_ai",
                    memberId: nil
                )
            ),
            for: threadID
        )

        try? await Task.sleep(nanoseconds: 600_000_000)
        let lastPayload = await repository.lastPayload
        XCTAssertEqual(lastPayload?.effectiveQuestionGenerationState, .generated)
        // generated payload 补齐 memberID
        XCTAssertEqual(lastPayload?.questionGeneration?.memberId, 10)
        XCTAssertEqual(lastPayload?.questions.count, 3)
    }

    func testGeneratedRejectedWhenThreadMemberChanged() async {
        let threadID = UUID()
        let thread = ChatThread(id: threadID, memberID: 10, title: "Test")
        let message = ChatGuideSystemMessageFactory.make(
            threadID: threadID,
            payload: generatingPayload(memberID: 10)
        )

        let repository = GuideCoordinatorTestRepository()
        await repository.seed(thread: thread, message: message)

        let runtime = SlowGuideQuestionRuntime(delayNanoseconds: 400_000_000)
        let coordinator = makeCoordinator(repository: repository, runtime: runtime)
        let stateStore = ChatStateStore()

        await coordinator.startForNewThread(
            threadID: threadID,
            messages: [message],
            stateStore: stateStore,
            resolveModelName: { _ in nil }
        )

        // AI 完成前用户切换成员：旧结果必须被拦截
        try? await Task.sleep(nanoseconds: 100_000_000)
        await repository.updateThreadMemberID(11, for: threadID)

        try? await Task.sleep(nanoseconds: 600_000_000)
        let lastPayload = await repository.lastPayload
        XCTAssertNotEqual(lastPayload?.effectiveQuestionGenerationState, .generated)
        XCTAssertNotEqual(lastPayload?.questionGeneration?.memberId, 10)
    }

    func testFallbackRejectedWhenThreadMemberChanged() async {
        let threadID = UUID()
        let thread = ChatThread(id: threadID, memberID: 10, title: "Test")
        let message = ChatGuideSystemMessageFactory.make(
            threadID: threadID,
            payload: generatingPayload(memberID: 10)
        )

        let repository = GuideCoordinatorTestRepository()
        await repository.seed(thread: thread, message: message)

        let runtime = SlowGuideQuestionRuntime(delayNanoseconds: 400_000_000, responses: ["not-json"])
        let coordinator = makeCoordinator(repository: repository, runtime: runtime)
        let stateStore = ChatStateStore()

        await coordinator.startForNewThread(
            threadID: threadID,
            messages: [message],
            stateStore: stateStore,
            resolveModelName: { _ in nil }
        )

        try? await Task.sleep(nanoseconds: 100_000_000)
        await repository.updateThreadMemberID(11, for: threadID)

        try? await Task.sleep(nanoseconds: 500_000_000)
        let lastPayload = await repository.lastPayload
        XCTAssertNotEqual(lastPayload?.questionGeneration?.memberId, 10)
        XCTAssertNotEqual(lastPayload?.effectiveQuestionGenerationState, .fallback)
    }

    // MARK: - 取消兜底

    func testCancelledWithoutTakeoverAppliesPreset() async {
        let threadID = UUID()
        let thread = ChatThread(id: threadID, memberID: 10, title: "Test")
        let message = ChatGuideSystemMessageFactory.make(
            threadID: threadID,
            payload: generatingPayload(memberID: 10)
        )

        let repository = GuideCoordinatorTestRepository()
        await repository.seed(thread: thread, message: message)

        let runtime = CancellingGuideQuestionRuntime()
        let coordinator = makeCoordinator(repository: repository, runtime: runtime)
        let stateStore = ChatStateStore()

        await coordinator.startForNewThread(
            threadID: threadID,
            messages: [message],
            stateStore: stateStore,
            resolveModelName: { _ in nil }
        )

        try? await Task.sleep(nanoseconds: 300_000_000)
        // 取消且无新任务接管：固定兜底修复，避免卡片永久 loading
        let lastPayload = await repository.lastPayload
        XCTAssertEqual(lastPayload?.effectiveQuestionGenerationState, .preset)
        XCTAssertEqual(lastPayload?.questions, ChatGuideQuestionPreset.phaseOne)
    }

    // MARK: - Helpers

    private func generatingPayload(memberID: Int?) -> ChatGuideCardPayload {
        var payload = ChatGuideCardPreviewFixtures.generatingPayload
        payload.memberId = memberID
        payload.questionGeneration = ChatGuideQuestionGenerationMeta(
            state: .generating,
            source: "current_chat_ai",
            memberId: memberID
        )
        return payload
    }

    private func generatedPayload(memberID: Int) -> ChatGuideCardPayload {
        ChatGuideCardPayload(
            schemaVersion: 2,
            generatedAt: Date(),
            memberId: memberID,
            metricSections: [],
            questions: Array(ChatGuideQuestionPreset.phaseOne.prefix(3)),
            questionGeneration: ChatGuideQuestionGenerationMeta(
                state: .generated,
                source: "current_chat_ai",
                memberId: memberID,
                generatedAt: Date()
            )
        )
    }

    private func fallbackPayload(memberID: Int) -> ChatGuideCardPayload {
        ChatGuideCardPayload(
            schemaVersion: 2,
            generatedAt: Date(),
            memberId: memberID,
            metricSections: [],
            questions: ChatGuideQuestionPreset.phaseOne,
            questionGeneration: ChatGuideQuestionGenerationMeta(
                state: .fallback,
                source: "preset",
                memberId: memberID,
                errorMessage: "ai_generation_failed"
            )
        )
    }

    private func presetPayload() -> ChatGuideCardPayload {
        ChatGuideCardPayload(
            schemaVersion: 2,
            generatedAt: Date(),
            memberId: nil,
            metricSections: [],
            questions: ChatGuideQuestionPreset.phaseOne,
            questionGeneration: ChatGuideQuestionGenerationMeta(
                state: .preset,
                source: "preset",
                memberId: nil
            )
        )
    }

    private func makeCoordinator(
        repository: GuideCoordinatorTestRepository,
        runtime: AIRuntimeServing
    ) -> ChatGuideQuestionGenerationCoordinator {
        let useCase = ChatGuideQuestionGenerationUseCase(
            runtime: runtime,
            medicalReader: StubGuideMedicalReader(
                completeData: StubGuideMedicalReader.makeCompleteData(
                    memberID: 10,
                    caseCount: 1,
                    activePlanCount: 0
                )
            )
        )
        return ChatGuideQuestionGenerationCoordinator(
            generationUseCase: useCase,
            chatRepository: repository,
            aiConfigCenter: AIConfigCenter(
                repository: GuideCoordinatorAISettingsRepository(),
                runtimeStore: AIRuntimeStore(),
                runtimeConfigStore: AIRuntimeConfigStore()
            ),
            aiSettingsRepository: GuideCoordinatorAISettingsRepository()
        )
    }
}

private actor GuideCoordinatorTestRepository: ChatRepository {
    private var threadByID: [UUID: ChatThread] = [:]
    private var threadMessages: [UUID: [ChatMessage]] = [:]
    private var messageThreadIndex: [UUID: UUID] = [:]
    private(set) var lastPayload: ChatGuideCardPayload?

    func seed(thread: ChatThread, message: ChatMessage) {
        threadByID[thread.id] = thread
        threadMessages[thread.id] = [message]
        messageThreadIndex[message.clientMessageID] = thread.id
    }

    func updateThreadMemberID(_ memberID: Int?, for threadID: UUID) {
        guard let thread = threadByID[threadID] else { return }
        threadByID[threadID] = ChatThread(
            id: thread.id,
            memberID: memberID,
            title: thread.title,
            scenario: thread.scenario,
            currentModelName: thread.currentModelName,
            temperature: thread.temperature,
            topP: thread.topP,
            maxTokens: thread.maxTokens,
            maxMessages: thread.maxMessages,
            rolePrompt: thread.rolePrompt,
            imageDeliveryModeRaw: thread.imageDeliveryModeRaw,
            iconName: thread.iconName,
            iconColorName: thread.iconColorName,
            isPinned: thread.isPinned,
            pinnedAt: thread.pinnedAt,
            isDeleted: thread.isDeleted,
            deletedAt: thread.deletedAt,
            createdAt: thread.createdAt,
            updatedAt: thread.updatedAt,
            serverUpdatedAt: thread.serverUpdatedAt
        )
    }

    func replaceMessages(_ messages: [ChatMessage], for threadID: UUID) {
        threadMessages[threadID] = messages
        for message in messages {
            messageThreadIndex[message.clientMessageID] = threadID
        }
    }

    /// 原地覆写 guide block payload（保留 message/block id），用于模拟历史数据或远端覆盖。
    func overwriteGuidePayload(_ payload: ChatGuideCardPayload, for threadID: UUID) {
        guard var messages = threadMessages[threadID] else { return }
        for index in messages.indices where messages[index].role == .system {
            let message = messages[index]
            let blocks = message.blocks.map { block -> ChatMessageBlock in
                guard block.kind == .chatGuideCard else { return block }
                return block.replacingPayload(.chatGuideCard(payload), status: .ready)
            }
            messages[index] = message.replacingBlocks(blocks)
        }
        threadMessages[threadID] = messages
    }

    func loadActiveThread() async -> ChatThread? { nil }
    func loadThread(id: UUID) async -> ChatThread? { threadByID[id] }
    func loadThreads() async -> [ChatThread] { Array(threadByID.values) }
    func loadThreadListItems() async -> [ChatThreadListItem] { [] }
    func loadThreadListItem(threadID: UUID) async -> ChatThreadListItem? { nil }
    func createThread(memberID: Int?, title: String, imageDeliveryModeRaw: String?, rolePrompt: String) async -> ChatThread {
        ChatThread(memberID: memberID, title: title)
    }
    func setActiveThread(id: UUID) async {}
    func updateThreadMemberBinding(threadID: UUID, memberID: Int?) async {
        updateThreadMemberID(memberID, for: threadID)
    }
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
    func countMessages(threadID: UUID) async -> Int { threadMessages[threadID]?.count ?? 0 }
    func latestServerActivity(for threadID: UUID) async -> Date? { nil }
    func appendMessage(_ message: ChatMessage) async throws -> ChatMessage { message }
    func upsertLocalMessage(_ message: ChatMessage) async throws -> ChatMessage { message }
    func softDeleteMessage(clientMessageID: UUID) async {}
    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState, notifyUI: Bool) async {}
    func applyPushMessageAck(clientMessageID: UUID, serverMessageID: String?, serverUpdatedAt: Date, notifyUI: Bool) async {}
    func updateMessageBlocks(clientMessageID: UUID, blocks: [ChatMessageBlock], markPendingForSync: Bool) async {}
    func upsertMessageBlock(clientMessageID: UUID, block: ChatMessageBlock, markPendingForSync: Bool) async -> Bool {
        guard case .chatGuideCard(let payload) = block.payload else { return false }
        lastPayload = payload
        guard let threadID = messageThreadIndex[clientMessageID] else { return true }
        var messages = threadMessages[threadID] ?? []
        guard let index = messages.firstIndex(where: { $0.clientMessageID == clientMessageID }) else {
            return true
        }
        let message = messages[index]
        let updatedBlocks = message.blocks.map { $0.id == block.id ? block : $0 }
        messages[index] = message.replacingBlocks(updatedBlocks)
        threadMessages[threadID] = messages
        return true
    }
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

private struct GuideCoordinatorAISettingsRepository: AISettingsRepository {
    func loadSnapshot(ownerAccountID: Int64?) async -> AISettingsSnapshot { .default }
    func save(snapshot: AISettingsSnapshot) async throws {}
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

private final class SlowGuideQuestionRuntime: AIRuntimeServing, @unchecked Sendable {
    private(set) var callCount = 0
    private let delayNanoseconds: UInt64
    private let responses: [String]

    init(delayNanoseconds: UInt64, responses: [String]? = nil) {
        self.delayNanoseconds = delayNanoseconds
        self.responses = responses ?? [
            """
            [
              {"id":"q1","title":"问题一?","prompt":"问题一完整?","category":"popular_science"},
              {"id":"q2","title":"问题二?","prompt":"问题二完整?","category":"popular_science"},
              {"id":"q3","title":"问题三?","prompt":"问题三完整?","category":"popular_science"}
            ]
            """
        ]
    }

    func generateTextStream(
        request: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error> {
        callCount += 1
        let index = min(callCount - 1, responses.count - 1)
        let text = responses[index]
        return AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                continuation.yield(
                    .completed(
                        AIRuntimeTextResponse(
                            text: text,
                            model: "stub",
                            promptTokens: nil,
                            completionTokens: nil,
                            toolCalls: [],
                            finishReason: "stop"
                        )
                    )
                )
                continuation.finish()
            }
        }
    }
}

private final class CancellingGuideQuestionRuntime: AIRuntimeServing, @unchecked Sendable {
    func generateTextStream(
        request: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: CancellationError())
        }
    }
}
#endif
