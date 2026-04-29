import Foundation

/// 聊天消息 blocks 元数据聚合层：
/// - 从消息 blocks 聚合 UI 可直接消费的结构化数据；
/// - 避免在 `ChatView` 内部散落解析逻辑。
struct ChatMessageMetadata {
    let toolName: String?
    let toolContent: String?
    let operationalState: String?
    let operationalDescription: String?
    let knowledgeCards: [ChatKnowledgeCard]
    let translatedText: String?
    let htmlContent: String?
    let locations: [ChatMapLocationPayload]
    let routes: [ChatRoutePayload]
    let events: [ChatEventPayload]
    let healthCards: [ChatHealthCardPayload]
    let sleepVisualization: ChatHealthSleepModel?
    let taskCards: [TaskCard]
    let pendingMemberToolCards: [PendingMemberToolCard]
    /// 对话内结构化医疗卡片（用药/处方/检查/病历），对应 `structuredHealthCards` block。
    let structuredHealthCards: StructuredHealthCardsBlob?
    let captureMessageCard: ChatCaptureMessageCardPayload?
    let smallTaskCard: ChatSmallTaskMessageCardPayload?

    init(message: ChatMessage) {
        let toolBlocks = message.blocks.filter { $0.kind == .tool }
        toolName = toolBlocks.last?.toolName
        toolContent = toolBlocks.last?.text
        if let meta = ChatToolRuntimeAttachmentBuilder.makeOperationalMeta(toolName: toolName, toolContent: toolContent) {
            operationalState = meta.state
            operationalDescription = meta.description.isEmpty ? nil : meta.description
        } else {
            operationalState = nil
            operationalDescription = nil
        }
        translatedText = message.blocks.last(where: { $0.kind == .translatedText })?.text
        htmlContent = message.blocks.last(where: { $0.kind == .html })?.text
        knowledgeCards = message.blocks
            .filter { $0.kind == .knowledgeCards }
            .flatMap(\.knowledgeCards)
        locations = message.blocks
            .filter { $0.kind == .mapRoute }
            .flatMap(\.locations)
        routes = message.blocks
            .filter { $0.kind == .mapRoute }
            .flatMap(\.routes)
        events = message.blocks
            .filter { $0.kind == .events }
            .flatMap(\.events)
        healthCards = message.blocks
            .filter { $0.kind == .healthCards }
            .flatMap(\.healthCards)
        sleepVisualization = message.blocks.last(where: { $0.kind == .sleepVisualization })?.sleepVisualization
        taskCards = message.blocks
            .filter { $0.kind == .taskCards }
            .flatMap(\.taskCards)
        pendingMemberToolCards = message.blocks
            .filter { $0.kind == .pendingMemberToolCards }
            .flatMap(\.pendingMemberToolCards)
        structuredHealthCards = message.blocks.last(where: { $0.kind == .structuredHealthCards })?.structuredHealthCards
        captureMessageCard = message.blocks.last(where: { $0.kind == .captureCard })?.captureMessageCard
        smallTaskCard = message.blocks.last(where: { $0.kind == .smallTaskCard })?.smallTaskCard
    }
}
