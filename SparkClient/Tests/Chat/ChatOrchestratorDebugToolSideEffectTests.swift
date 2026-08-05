#if canImport(XCTest)
import Foundation
import XCTest

final class ChatOrchestratorDebugToolSideEffectTests: XCTestCase {
    func testDebugSlashCommandEarlyExitAppliesToolSideEffectsViaMessageRunActor() async {
        let repository = RecordingChatRepository()
        let actor = MessageRunActor(repository: repository)
        let threadID = UUID()
        let assistantID = UUID()

        try? await actor.startAssistantMessage(
            threadID: threadID,
            assistantClientMessageID: assistantID,
            modelName: "test-model"
        )

        let cards = [ChatKnowledgeCard(title: "Debug", content: "From slash tool", showsSaveAndCopy: false)]
        let result = ToolExecutionResult(
            toolName: SparkToolName.searchKnowledgeBag,
            outputText: "From slash tool",
            sensitive: false,
            shouldBypassModel: true,
            sideEffects: [.knowledgeCards(cards)]
        )

        for effect in result.sideEffects {
            await actor.apply(
                .toolSideEffect(
                    effect,
                    anchorToolCallID: nil,
                    assistantClientMessageID: assistantID
                )
            )
        }

        let recordedKinds = await repository.recordedBlockKinds()
        XCTAssertEqual(recordedKinds, [.knowledgeCards])

        let messages = await repository.loadMessages(clientMessageIDs: [assistantID])
        XCTAssertEqual(messages.first?.blocks.count, 1)
        XCTAssertEqual(messages.first?.blocks.first?.kind, .knowledgeCards)
    }
}

private actor RecordingChatRepository: ChatRepository {
    private var messages: [UUID: ChatMessage] = [:]
    private var blockKinds: [ChatMessageBlockKind] = []

    func recordedBlockKinds() -> [ChatMessageBlockKind] {
        blockKinds
    }

    func loadActiveThread() async -> ChatThread? { nil }
    func loadThread(id: UUID) async -> ChatThread? { nil }
    func loadThreads() async -> [ChatThread] { [] }
    func loadThreadListItems() async -> [ChatThreadListItem] { [] }
    func loadThreadListItem(threadID: UUID) async -> ChatThreadListItem? { nil }
    func createThread(memberID: Int?, title: String, imageDeliveryModeRaw: String?, rolePrompt: String) async -> ChatThread {
        fatalError("Not implemented")
    }
    func setActiveThread(id: UUID) async {}
    func updateThreadMemberBinding(threadID: UUID, memberID: Int?) async {}
    func updateThreadImageDeliveryMode(threadID: UUID, imageDeliveryModeRaw: String?) async {}
    func updateThreadCurrentModelName(threadID: UUID, currentModelName: String?) async {}
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
    func loadMessages(clientMessageIDs: [UUID]) async -> [ChatMessage] {
        clientMessageIDs.compactMap { messages[$0] }
    }
    func countMessages(threadID: UUID) async -> Int { 0 }
    func latestServerActivity(for threadID: UUID) async -> Date? { nil }
    func appendMessage(_ message: ChatMessage) async throws -> ChatMessage { message }
    func upsertLocalMessage(_ message: ChatMessage) async throws -> ChatMessage {
        messages[message.clientMessageID ?? message.id] = message
        return message
    }
    func softDeleteMessage(clientMessageID: UUID) async {}
    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState) async {}
    func applyPushMessageAck(clientMessageID: UUID, serverMessageID: String?, serverUpdatedAt: Date) async {}
    func updateMessageBlocks(clientMessageID: UUID, blocks: [ChatMessageBlock], markPendingForSync: Bool) async {}
    func upsertMessageBlock(clientMessageID: UUID, block: ChatMessageBlock, markPendingForSync: Bool) async -> Bool {
        blockKinds.append(block.kind)
        guard var message = messages[clientMessageID] else { return false }
        if let index = message.blocks.firstIndex(where: { $0.id == block.id }) {
            message.blocks[index] = block
        } else {
            message.blocks.append(block)
        }
        messages[clientMessageID] = message
        return true
    }
    func upsertRemoteMessages(_ messages: [ChatMessage], in threadID: UUID, enqueueAttachmentDownloadJobs: Bool) async {}
    func loadOutboxMessages(limit: Int) async -> [ChatMessage] { [] }
    func loadPendingMessageBlocks(limit: Int) async -> [ChatPendingMessageBlock] { [] }
    func markMessageBlocksSynced(ids: [UUID]) async {}

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
#endif
