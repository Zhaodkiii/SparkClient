import Foundation

/// 富卡片事件工厂。
///
/// 这个类型不读取数据库、不轮询等待消息、不合并数组。工具后台任务只把业务结果
/// 转成稳定 ID 的 `ChatRunEvent`，再交给 `MessageRunActor` 串行写入
/// `ChatMessageBlockEntity`。消息是否存在、revision 幂等、服务端待同步标记和 UI 刷新
/// 都由 Actor -> Repository -> Core Data 这一条管道处理。
final class StructuredHealthCardMergeCoordinator: @unchecked Sendable {
    private let messageRunActor: MessageRunActor
    private let pushOutbox: @Sendable () async throws -> Void
    private let logger: Logger

    init(
        messageRunActor: MessageRunActor,
        pushOutbox: @escaping @Sendable () async throws -> Void,
        logger: Logger = ConsoleLogger()
    ) {
        self.messageRunActor = messageRunActor
        self.pushOutbox = pushOutbox
        self.logger = logger
    }

    func publishRichBlocks(
        threadID: UUID,
        assistantClientMessageID: UUID,
        blocks: [ChatMessageBlock]
    ) async {
        await submit(blocks, assistantClientMessageID: assistantClientMessageID)
    }

    @discardableResult
    func publishHealthStructuredHealthCardsPending(
        threadID: UUID,
        assistantClientMessageID: UUID,
        anchorToolCallID: String?
    ) async -> Bool {
        return await publishHealthStructuredHealthCards(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            blob: .empty,
            anchorToolCallID: anchorToolCallID,
            status: .pending
        )
    }

    func publishStructuredHealthCardsFailed(
        assistantClientMessageID: UUID,
        anchorToolCallID: String?,
        message: String? = nil
    ) async {
        await submit(
            [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .structuredHealthCards,
                    toolCallID: anchorToolCallID,
                    structuredHealthCards: .failed(message: message ?? ""),
                    status: .failed
                )
            ],
            assistantClientMessageID: assistantClientMessageID
        )
    }

    @discardableResult
    func publishHealthStructuredHealthCards(
        threadID: UUID,
        assistantClientMessageID: UUID,
        blob: StructuredHealthCardsBlob,
        anchorToolCallID: String? = nil,
        status: ChatMessageBlockStatus = .ready
    ) async -> Bool {
        if status == .ready, blob.hasDisplayableCards == false {
            logger.warning(
                "结构化健康卡片 ready 发布跳过：抽取结果无卡片条目（examReports=\(blob.examReports.count), medicationPlans=\(blob.medicationPlans.count), medicineBoxes=\(blob.medicineBoxes.count), prescriptions=\(blob.prescriptions.count), medicalCases=\(blob.medicalCases.count)），assistantMessageClientID=\(assistantClientMessageID.uuidString)",
                module: .aiConfig
            )
            await publishStructuredHealthCardsFailed(
                assistantClientMessageID: assistantClientMessageID,
                anchorToolCallID: anchorToolCallID
            )
            return false
        }
        guard isEncodable(blob) else {
            logger.warning("结构化健康卡片发布跳过：payload 无法编码", module: .aiConfig)
            return false
        }
        let didApply = await submit(
            [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .structuredHealthCards,
                    toolCallID: anchorToolCallID,
                    structuredHealthCards: blob,
                    status: status
                )
            ],
            assistantClientMessageID: assistantClientMessageID
        )

        if status == .pending {
            return didApply
        }
        guard status == .ready else { return didApply }
        guard didApply else {
            logger.warning(
                "结构化健康卡片 ready 写入未生效，跳过独立上送，assistantMessageClientID=\(assistantClientMessageID.uuidString)",
                module: .aiConfig
            )
            return false
        }
        logger.info(
            "结构化健康卡片 ready 已落库，cards=\(blob.totalCardCount)，assistantMessageClientID=\(assistantClientMessageID.uuidString)，准备独立上送 outbox",
            module: .aiConfig
        )
        do {
            try await pushOutbox()
        } catch {
            logger.warning(
                "结构化健康卡片 ready 后上送 outbox 失败：\(error.localizedDescription)",
                module: .aiConfig
            )
        }
        return true
    }

    func publishAssistantTimelineNotice(
        assistantClientMessageID: UUID,
        text: String
    ) async {
        await messageRunActor.appendTimelineNotice(text, assistantClientMessageID: assistantClientMessageID)
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

    @discardableResult
    private func submit(
        _ blocks: [ChatMessageBlock],
        assistantClientMessageID: UUID
    ) async -> Bool {
        var didApplyAny = false
        for block in blocks {
            let didApply = await messageRunActor.apply(
                .richBlockReady(block, assistantClientMessageID: assistantClientMessageID)
            )
            didApplyAny = didApplyAny || didApply
        }
        return didApplyAny
    }
    
    

    private func isEncodable<T: Encodable>(_ value: T) -> Bool {
        (try? JSONEncoder.default.encode(value)) != nil
    }
}
