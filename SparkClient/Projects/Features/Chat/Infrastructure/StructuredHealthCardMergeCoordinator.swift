import Foundation

/// 统一协调“消息内卡片展示”流程：
/// 1. 先把 patch 实时合并进流式消息
/// 2. 等正式 assistant 消息落库
/// 3. 将同一份 patch 落库并标记待同步
///
/// 这里不再区分“附件路径”和“卡片路径”，统一收口为 presentation patch。
final class StructuredHealthCardMergeCoordinator: @unchecked Sendable {
    private struct PresentationPatch: Sendable {
        let attachments: [ChatAttachment]
        let blocks: [ChatMessageBlock]

        var isEmpty: Bool {
            attachments.isEmpty && blocks.isEmpty
        }

        static func from(attachments: [ChatAttachment], createdAt: Date = Date()) -> PresentationPatch {
            PresentationPatch(
                attachments: attachments,
                blocks: ChatMessageBlockBuilder.blocks(from: attachments, createdAt: createdAt)
            )
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

    func mergeRichAttachmentsIntoStreamingCache(
        threadID: UUID,
        attachments: [ChatAttachment]
    ) async {
        await mergeRichPresentationIntoStreamingCache(threadID: threadID, patch: .from(attachments: attachments))
    }

    func mergeRichPresentationIntoStreamingCache(
        threadID: UUID,
        attachments: [ChatAttachment],
        blocks: [ChatMessageBlock]
    ) async {
        await mergeRichPresentationIntoStreamingCache(
            threadID: threadID,
            patch: PresentationPatch(attachments: attachments, blocks: blocks)
        )
    }

    func mergeAppendRichAttachmentsWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        attachments: [ChatAttachment],
        maxWaitSeconds: TimeInterval = 300
    ) async {
        await mergeAppendRichPresentationWhenAssistantMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            patch: .from(attachments: attachments),
            maxWaitSeconds: maxWaitSeconds
        )
    }

    func mergeAppendRichPresentationWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        attachments: [ChatAttachment],
        blocks: [ChatMessageBlock],
        maxWaitSeconds: TimeInterval = 300
    ) async {
        await mergeAppendRichPresentationWhenAssistantMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            patch: PresentationPatch(attachments: attachments, blocks: blocks),
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
            guard let data = try? JSONEncoder().encode(blob),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return PresentationPatch(
                attachments: Self.replacingAttachment(
                    in: message.attachments,
                    with: ChatAttachment(type: .structuredHealthCards, text: json)
                ),
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
        guard let data = try? JSONEncoder().encode(blob),
              let json = String(data: data, encoding: .utf8) else { return }

        let patch = PresentationPatch(
            attachments: Self.replacingAttachment(
                in: message.attachments,
                with: ChatAttachment(type: .structuredHealthCards, text: json)
            ),
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
        struct Row: Codable {
            let title: String
            let content: String
        }

        guard let data = try? JSONEncoder().encode([Row(title: title, content: content)]),
              let json = String(data: data, encoding: .utf8) else { return }

        await mergeAppendRichAttachmentsWhenAssistantMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            attachments: [ChatAttachment(type: .knowledgeCard, text: json)],
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
        guard let data = try? JSONEncoder().encode(model),
              let json = String(data: data, encoding: .utf8) else { return }

        let patch = PresentationPatch(
            attachments: [
                ChatAttachment(
                    type: .healthSleepVisualization,
                    text: json,
                    anchorToolCallID: anchorToolCallID
                )
            ],
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
        await waitUntilMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            maxWaitSeconds: maxWaitSeconds
        ) { message in
            // Wait until the anchor target block (sleep tool call) is present in the persisted
            // message blocks. If we commit before persistStreamingAttachmentsIfNeeded has run,
            // existingBlocks will be empty and the sleep viz block gets saved at index 0 (top),
            // causing the anchor-based re-insertion in the subsequent merge to corrupt the order.
            if let anchorID = anchorToolCallID {
                guard message.blocks.contains(where: { $0.toolCallID == anchorID }) else {
                    return nil
                }
            }
            let attachment = ChatAttachment(
                type: .healthSleepVisualization,
                text: json,
                anchorToolCallID: anchorToolCallID
            )
            return PresentationPatch(
                attachments: Self.replacingAttachment(in: message.attachments, with: attachment),
                blocks: [
                    ChatMessageBlock(
                        anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                        kind: .sleepVisualization,
                        toolCallID: anchorToolCallID,
                        sleepVisualization: model,
                        createdAt: message.createdAt,
                        updatedAt: Date()
                    )
                ]
            )
        }
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(taskCards),
              let json = String(data: data, encoding: .utf8) else { return }

        let patch = PresentationPatch(
            attachments: [
                ChatAttachment(
                    type: .taskCards,
                    text: json,
                    anchorToolCallID: anchorToolCallID
                )
            ],
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
        await waitUntilMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            maxWaitSeconds: maxWaitSeconds
        ) { message in
            if let anchorID = anchorToolCallID {
                guard message.blocks.contains(where: { $0.toolCallID == anchorID }) else {
                    return nil
                }
            }
            let attachment = ChatAttachment(
                type: .taskCards,
                text: json,
                anchorToolCallID: anchorToolCallID
            )
            return PresentationPatch(
                attachments: Self.replacingAttachment(in: message.attachments, with: attachment),
                blocks: [
                    ChatMessageBlock(
                        anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                        kind: .taskCards,
                        toolCallID: anchorToolCallID,
                        taskCards: taskCards,
                        createdAt: message.createdAt,
                        updatedAt: Date()
                    )
                ]
            )
        }
    }

    func insertCaptureCardWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        payload: ChatCaptureMessageCardPayload,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        await waitUntilMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            maxWaitSeconds: maxWaitSeconds
        ) { message in
            guard let data = try? JSONEncoder().encode(payload),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return PresentationPatch(
                attachments: Self.replacingAttachment(
                    in: message.attachments,
                    with: ChatAttachment(type: .captureMessageCard, text: json)
                ),
                blocks: [
                    ChatMessageBlock(
                        kind: .captureCard,
                        captureMessageCard: payload,
                        createdAt: message.createdAt,
                        updatedAt: Date()
                    )
                ]
            )
        }
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
                attachments: patch.attachments,
                blocks: patch.blocks
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
        let combinedAttachments = mergeAttachments(base: message.attachments, overlay: patch.attachments)
        let combinedBlocks = ChatMessageBlockBuilder.mergeRichBlocks(
            existingBlocks: message.blocks,
            incomingBlocks: patch.blocks
        )

        await repository.updateMessagePresentation(
            clientMessageID: assistantClientMessageID,
            attachments: combinedAttachments,
            blocks: combinedBlocks,
            markPendingForSync: true
        )

        let store = stateStore
        await MainActor.run {
            store?.updateMessagePresentation(
                threadID: threadID,
                clientMessageID: assistantClientMessageID,
                attachments: combinedAttachments,
                blocks: combinedBlocks
            )
        }
    }

    // MARK: - Helpers

    private func mergeAttachments(base: [ChatAttachment], overlay: [ChatAttachment]) -> [ChatAttachment] {
        var merged = base
        for attachment in overlay {
            if let index = merged.firstIndex(where: { existing in
                existing.type == attachment.type
                    && existing.anchorToolCallID == attachment.anchorToolCallID
                    && existing.anchorBlockID == attachment.anchorBlockID
            }) {
                merged[index] = attachment
            } else {
                merged.append(attachment)
            }
        }
        return merged
    }

    private static func replacingAttachment(
        in attachments: [ChatAttachment],
        with replacement: ChatAttachment
    ) -> [ChatAttachment] {
        var out = attachments
        if let index = out.firstIndex(where: {
            $0.type == replacement.type
                && $0.anchorToolCallID == replacement.anchorToolCallID
                && $0.anchorBlockID == replacement.anchorBlockID
        }) {
            out[index] = replacement
        } else {
            out.append(replacement)
        }
        return out
    }

    private static func decodeStructuredHealthBlob(from message: ChatMessage) -> StructuredHealthCardsBlob? {
        guard let raw = message.attachments.first(where: { $0.type == .structuredHealthCards })?.text,
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(StructuredHealthCardsBlob.self, from: data)
    }
}
