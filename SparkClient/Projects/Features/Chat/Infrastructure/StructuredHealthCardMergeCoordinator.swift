import Foundation

/// 统一协调“消息内卡片展示”流程：
/// 1. 先把 patch 实时合并进流式消息
/// 2. 等正式 assistant 消息落库
/// 3. 将同一份 patch 落库并标记待同步
///
/// 这里统一走 blocks patch，不再区分历史分支。
final class StructuredHealthCardMergeCoordinator: @unchecked Sendable {
    private struct PresentationPatch: Sendable {
        let blocks: [ChatMessageBlock]

        var isEmpty: Bool {
            blocks.isEmpty
        }

        var requiresDatabaseMerge: Bool {
            blocks.contains { $0.kind == .structuredHealthCards }
        }
    }

    private let repository: any ChatRepository
    private weak var stateStore: ChatStateStore?

    init(repository: any ChatRepository) {
        self.repository = repository
    }

    func register(stateStore: ChatStateStore) {
        self.stateStore = stateStore
    }

    // MARK: - Public streaming / async entry points

    func mergeRichPresentationIntoStreamingCache(
        threadID: UUID,
        blocks: [ChatMessageBlock]
    ) async {
        await mergeRichPresentationIntoStreamingCache(
            threadID: threadID,
            patch: PresentationPatch(blocks: blocks)
        )
    }

    func mergeAppendRichPresentationWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        blocks: [ChatMessageBlock],
        maxWaitSeconds: TimeInterval = 300
    ) async {
        await mergeAppendRichPresentationWhenAssistantMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            patch: PresentationPatch(blocks: blocks),
            maxWaitSeconds: maxWaitSeconds
        )
    }

    func mergeAppendWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        delta: StructuredHealthCardsBlob,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        await waitUntilMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            maxWaitSeconds: maxWaitSeconds
        ) { message in
            var blob = Self.decodeStructuredHealthBlob(from: message) ?? .empty
            blob.medications.append(contentsOf: delta.medications)
            blob.prescriptions.append(contentsOf: delta.prescriptions)
            blob.examReports.append(contentsOf: delta.examReports)
            blob.medicalCases.append(contentsOf: delta.medicalCases)
            guard (try? JSONEncoder().encode(blob)) != nil else {
                return nil
            }
            return PresentationPatch(
                blocks: [
                    ChatMessageBlock(
                        kind: .structuredHealthCards,
                        structuredHealthCards: blob,
                        createdAt: message.createdAt,
                        updatedAt: Date()
                    )
                ]
            )
        }
    }

    func mergeAppend(
        threadID: UUID,
        assistantClientMessageID: UUID,
        delta: StructuredHealthCardsBlob
    ) async {
        let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
        guard let message = messages.first(where: { $0.clientMessageID == assistantClientMessageID }) else { return }

        var blob = Self.decodeStructuredHealthBlob(from: message) ?? .empty
        blob.medications.append(contentsOf: delta.medications)
        blob.prescriptions.append(contentsOf: delta.prescriptions)
        blob.examReports.append(contentsOf: delta.examReports)
        blob.medicalCases.append(contentsOf: delta.medicalCases)
        guard (try? JSONEncoder().encode(blob)) != nil else { return }

        let patch = PresentationPatch(
            blocks: [
                ChatMessageBlock(
                    kind: .structuredHealthCards,
                    structuredHealthCards: blob,
                    createdAt: message.createdAt,
                    updatedAt: Date()
                )
            ]
        )
        await commitPatch(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            message: message,
            patch: patch
        )
    }

    func mergeKnowledgeCardPreviewWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        title: String,
        content: String,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        await mergeAppendRichPresentationWhenAssistantMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            blocks: [
                ChatMessageBlock(
                    kind: .knowledgeCards,
                    knowledgeCards: [ChatKnowledgeCard(title: title, content: content)]
                )
            ],
            maxWaitSeconds: maxWaitSeconds
        )
    }

    func insertHealthSleepVisualizationWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        model: ChatHealthSleepModel,
        anchorToolCallID: String? = nil,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        guard (try? JSONEncoder().encode(model)) != nil else { return }

        let patch = PresentationPatch(
            blocks: [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .sleepVisualization,
                    toolCallID: anchorToolCallID,
                    sleepVisualization: model
                )
            ]
        )

        await mergeRichPresentationIntoStreamingCache(threadID: threadID, patch: patch)
    }

    /// 与 `insertHealthSleepVisualizationWhenAssistantMessageReady` 同构：先合入流式缓存，再在助手消息已落库且锚点工具行存在时写入持久化与待同步。
    func insertTaskCardsWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        taskCards: [TaskCard],
        anchorToolCallID: String? = nil,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        guard taskCards.isEmpty == false else { return }
        let patch = PresentationPatch(
            blocks: [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .taskCards,
                    toolCallID: anchorToolCallID,
                    taskCards: taskCards
                )
            ]
        )

        await mergeRichPresentationIntoStreamingCache(threadID: threadID, patch: patch)
    }

    func insertCaptureCardWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        payload: ChatCaptureMessageCardPayload,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        guard (try? JSONEncoder().encode(payload)) != nil else { return }
        await mergeRichPresentationIntoStreamingCache(
            threadID: threadID,
            patch: PresentationPatch(
                blocks: [
                    ChatMessageBlock(
                        kind: .captureCard,
                        captureMessageCard: payload
                    )
                ]
            )
        )
    }

    // MARK: - Core pipeline

    private func mergeRichPresentationIntoStreamingCache(
        threadID: UUID,
        patch: PresentationPatch
    ) async {
        guard patch.isEmpty == false else { return }
        let store = stateStore
        await MainActor.run {
            store?.mergeStreamingAssistantPresentation(
                threadID: threadID,
                incomingBlocks: patch.blocks
            )
        }
    }

    private func mergeAppendRichPresentationWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        patch: PresentationPatch,
        maxWaitSeconds: TimeInterval
    ) async {
        guard patch.isEmpty == false else { return }
        await mergeRichPresentationIntoStreamingCache(threadID: threadID, patch: patch)
        guard patch.requiresDatabaseMerge else { return }
        await waitUntilMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            maxWaitSeconds: maxWaitSeconds
        ) { _ in patch }
    }

    private func waitUntilMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        maxWaitSeconds: TimeInterval,
        makePatch: (ChatMessage) -> PresentationPatch?
    ) async {
        let deadline = Date().addingTimeInterval(maxWaitSeconds)
        while Date() < deadline {
            let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
            if let message = messages.first(where: { $0.clientMessageID == assistantClientMessageID }),
               let patch = makePatch(message) {
                await commitPatch(
                    threadID: threadID,
                    assistantClientMessageID: assistantClientMessageID,
                    message: message,
                    patch: patch
                )
                return
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
    }

    private func commitPatch(
        threadID: UUID,
        assistantClientMessageID: UUID,
        message: ChatMessage,
        patch: PresentationPatch
    ) async {
        guard patch.isEmpty == false else { return }
        let combinedBlocks = ChatMessageBlockBuilder.mergeRichBlocks(
            existingBlocks: message.blocks,
            incomingBlocks: patch.blocks
        )

        await repository.updateMessageBlocks(
            clientMessageID: assistantClientMessageID,
            blocks: combinedBlocks,
            markPendingForSync: true
        )

        let store = stateStore
        await MainActor.run {
            store?.updateMessageBlocksSnapshot(
                threadID: threadID,
                clientMessageID: assistantClientMessageID,
                blocks: combinedBlocks
            )
        }
    }

    private static func decodeStructuredHealthBlob(from message: ChatMessage) -> StructuredHealthCardsBlob? {
        message.blocks.last(where: { $0.kind == .structuredHealthCards })?.structuredHealthCards
    }
}
