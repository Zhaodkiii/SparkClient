import Foundation

/// 将工具副作用映射为可落库的 `ChatMessageBlock`（`MessageRunActor` 仅负责 revision/orderKey）。
enum ToolSideEffectBlockMapper {
    static func blocks(
        for effect: ToolSideEffect,
        assistantClientMessageID: UUID,
        normalizedAnchor: String?,
        healthResourceRefIndex: Int? = nil
    ) -> [ChatMessageBlock]? {
        switch effect {
        case .healthResourceReference(let resourceType, let resourceID, let memberID):
            guard let refIndex = healthResourceRefIndex else { return nil }
            let payload = ChatHealthResourceReferencePayload(
                identity: HealthResourceIdentity(
                    resourceType: resourceType,
                    resourceID: resourceID,
                    memberID: memberID
                ),
                refIndex: refIndex
            )
            guard isEncodable(payload) else { return nil }
            let parentBlockID = normalizedAnchor.map {
                ChatStableBlockID.tool(messageID: assistantClientMessageID, toolCallID: $0)
            }
            return [
                ChatMessageBlock(
                    id: ChatStableBlockID.healthResource(
                        messageID: assistantClientMessageID,
                        resourceType: resourceType,
                        resourceID: resourceID,
                        memberID: memberID
                    ),
                    anchor: normalizedAnchor.map(ChatBlockAnchor.toolCall),
                    kind: .healthResourceReference,
                    toolCallID: normalizedAnchor,
                    parentToolCallID: normalizedAnchor,
                    parentBlockID: parentBlockID,
                    healthResourceReference: payload,
                    status: .ready
                )
            ]
        case .knowledgeCards(let cards):
            guard cards.isEmpty == false, isEncodable(cards) else { return nil }
            return [
                ChatMessageBlock(
                    anchor: normalizedAnchor.map(ChatBlockAnchor.toolCall),
                    kind: .knowledgeCards,
                    toolCallID: normalizedAnchor,
                    parentToolCallID: normalizedAnchor,
                    knowledgeCards: cards
                )
            ]
        case .taskCards(let taskCards):
            guard taskCards.isEmpty == false, isEncodable(taskCards) else { return nil }
            return [
                ChatMessageBlock(
                    anchor: normalizedAnchor.map(ChatBlockAnchor.toolCall),
                    kind: .taskCards,
                    toolCallID: normalizedAnchor,
                    parentToolCallID: normalizedAnchor,
                    taskCards: taskCards
                )
            ]
        case .captureCard(let payload):
            guard isEncodable(payload) else { return nil }
            return [
                ChatMessageBlock(
                    anchor: normalizedAnchor.map(ChatBlockAnchor.toolCall),
                    kind: .captureCard,
                    toolCallID: normalizedAnchor,
                    parentToolCallID: normalizedAnchor,
                    captureMessageCard: payload
                )
            ]
        case .workoutVisualization(let model):
            guard isEncodable(model) else { return nil }
            return [
                ChatMessageBlock(
                    anchor: normalizedAnchor.map(ChatBlockAnchor.toolCall),
                    kind: .workoutVisualization,
                    toolCallID: normalizedAnchor,
                    parentToolCallID: normalizedAnchor,
                    workoutVisualization: model
                )
            ]
        case .sleepVisualization(let model):
            guard isEncodable(model) else { return nil }
            return [
                ChatMessageBlock(
                    anchor: normalizedAnchor.map(ChatBlockAnchor.toolCall),
                    kind: .sleepVisualization,
                    toolCallID: normalizedAnchor,
                    parentToolCallID: normalizedAnchor,
                    sleepVisualization: model
                )
            ]
        case .nutritionCards(let cards):
            guard cards.isEmpty == false else { return nil }
            let payload = ChatNutritionCardsPayload(cards: cards)
            guard isEncodable(payload) else { return nil }
            return [
                ChatMessageBlock(
                    anchor: normalizedAnchor.map(ChatBlockAnchor.toolCall),
                    kind: .nutritionCards,
                    toolCallID: normalizedAnchor,
                    parentToolCallID: normalizedAnchor,
                    nutritionCards: payload
                )
            ]
        case .externalConnectorRichBlocks(let blocks):
            return blocks.isEmpty ? nil : blocks
        case .structuredHealthCardsPending,
             .structuredHealthCardsReady,
             .structuredHealthCardsFailed,
             .timelineNotice,
             .medicalRiskNotice:
            return nil
        }
    }

    private static func isEncodable<T: Encodable>(_ value: T) -> Bool {
        (try? JSONEncoder().encode(value)) != nil
    }
}
