import Foundation

/// 富卡片事件工厂。
///
/// 这个类型不读取数据库、不轮询等待消息、不合并数组。工具后台任务只把业务结果
/// 转成稳定 ID 的 `ChatRunEvent`，再交给 `MessageRunActor` 串行写入
/// `ChatMessageBlockEntity`。消息是否存在、revision 幂等、服务端待同步标记和 UI 刷新
/// 都由 Actor -> Repository -> Core Data 这一条管道处理。
final class StructuredHealthCardMergeCoordinator: @unchecked Sendable {
    private let messageRunActor: MessageRunActor
    private let logger: Logger

    init(messageRunActor: MessageRunActor, logger: Logger = ConsoleLogger()) {
        self.messageRunActor = messageRunActor
        self.logger = logger
    }

    func publishRichBlocks(
        threadID: UUID,
        assistantClientMessageID: UUID,
        blocks: [ChatMessageBlock]
    ) async {
        await submit(blocks, assistantClientMessageID: assistantClientMessageID)
    }

    func publishStructuredHealthCardsDelta(
        threadID: UUID,
        assistantClientMessageID: UUID,
        delta: StructuredHealthCardsBlob
    ) async {
        await messageRunActor.apply(
            .structuredHealthCardsDelta(
                delta,
                threadID: threadID,
                assistantClientMessageID: assistantClientMessageID
            )
        )
    }

    func publishStructuredHealthCards(
        threadID: UUID,
        assistantClientMessageID: UUID,
        delta: StructuredHealthCardsBlob,
        anchorToolCallID: String? = nil
    ) async {
        guard isEncodable(delta) else {
            logger.warning("结构化健康卡片发布跳过：payload 无法编码", module: .aiConfig)
            return
        }
        await submit(
            [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .structuredHealthCards,
                    toolCallID: anchorToolCallID,
                    structuredHealthCards: delta
                )
            ],
            assistantClientMessageID: assistantClientMessageID
        )
    }

    func publishStructuredHealthCardsPending(
        threadID: UUID,
        assistantClientMessageID: UUID,
        anchorToolCallID: String? = nil
    ) async {
        await submit(
            [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .structuredHealthCards,
                    toolCallID: anchorToolCallID,
                    structuredHealthCards: StructuredHealthCardsBlob(
                        medications: [],
                        prescriptions: [],
                        examReports: [],
                        medicalCases: []
                    ),
                    status: .pending
                )
            ],
            assistantClientMessageID: assistantClientMessageID
        )
    }

    func publishKnowledgeCardPreview(
        threadID: UUID,
        assistantClientMessageID: UUID,
        title: String,
        content: String
    ) async {
        await publishKnowledgeCards(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            cards: [ChatKnowledgeCard(title: title, content: content)],
            anchorToolCallID: nil
        )
    }

    func publishKnowledgeCards(
        threadID: UUID,
        assistantClientMessageID: UUID,
        cards: [ChatKnowledgeCard],
        anchorToolCallID: String? = nil
    ) async {
        guard cards.isEmpty == false, isEncodable(cards) else { return }
        await submit(
            [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .knowledgeCards,
                    toolCallID: anchorToolCallID,
                    knowledgeCards: cards
                )
            ],
            assistantClientMessageID: assistantClientMessageID
        )
    }

    func publishHealthWorkoutVisualization(
        threadID: UUID,
        assistantClientMessageID: UUID,
        model: ChatHealthWorkoutModel,
        anchorToolCallID: String? = nil
    ) async {
        guard isEncodable(model) else {
            logger.warning("运动可视化卡片发布跳过：payload 无法编码", module: .aiConfig)
            return
        }
        await submit(
            [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .workoutVisualization,
                    toolCallID: anchorToolCallID,
                    workoutVisualization: model
                )
            ],
            assistantClientMessageID: assistantClientMessageID
        )
    }

    func publishHealthSleepVisualization(
        threadID: UUID,
        assistantClientMessageID: UUID,
        model: ChatHealthSleepModel,
        anchorToolCallID: String? = nil
    ) async {
        guard isEncodable(model) else {
            logger.warning("睡眠可视化卡片发布跳过：payload 无法编码", module: .aiConfig)
            return
        }
        await submit(
            [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .sleepVisualization,
                    toolCallID: anchorToolCallID,
                    sleepVisualization: model
                )
            ],
            assistantClientMessageID: assistantClientMessageID
        )
    }

    func publishTaskCards(
        threadID: UUID,
        assistantClientMessageID: UUID,
        taskCards: [TaskCard],
        anchorToolCallID: String? = nil
    ) async {
        guard taskCards.isEmpty == false, isEncodable(taskCards) else { return }
        await submit(
            [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .taskCards,
                    toolCallID: anchorToolCallID,
                    taskCards: taskCards
                )
            ],
            assistantClientMessageID: assistantClientMessageID
        )
    }

    func publishCaptureCard(
        threadID: UUID,
        assistantClientMessageID: UUID,
        payload: ChatCaptureMessageCardPayload,
        anchorToolCallID: String? = nil
    ) async {
        guard isEncodable(payload) else { return }
        await submit(
            [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .captureCard,
                    toolCallID: anchorToolCallID,
                    captureMessageCard: payload
                )
            ],
            assistantClientMessageID: assistantClientMessageID
        )
    }

    private func submit(
        _ blocks: [ChatMessageBlock],
        assistantClientMessageID: UUID
    ) async {
        for block in blocks {
            await messageRunActor.apply(
                .richBlockReady(block, assistantClientMessageID: assistantClientMessageID)
            )
        }
    }

    private func isEncodable<T: Encodable>(_ value: T) -> Bool {
        (try? JSONEncoder.default.encode(value)) != nil
    }
}
