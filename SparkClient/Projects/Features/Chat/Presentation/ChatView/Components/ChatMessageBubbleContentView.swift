import SwiftUI
import UIKit

/// 单条消息气泡内容：
/// - 纯渲染组件，不直接持有全局状态；
/// - 通过入参和回调与上层协作。
struct ChatMessageBubbleContentView: View {
    let message: ChatMessage
    let metadata: ChatMessageMetadata
    let isLastAssistantMessage: Bool
    let translatedText: String?
    let combinedKnowledgeCards: [ChatKnowledgeCard]
    let isMathMode: Bool
    let conversationCardStyle: ChatConversationCardStyle
    let toolTraceDisplayMode: ChatToolTraceDisplayMode
    let collapseToolsWhileStreaming: Bool
    let separatesToolPresentationsInBodyFocused: Bool
    let isTranslating: Bool
    let isSavingMessage: Bool
    let isSavedMessage: Bool
    let isSpeaking: Bool
    let taskCardLoadingIDs: Set<Int>
    let ignoredTaskCardIDs: Set<Int>
    let createdTaskCardIDs: Set<Int>
    let savingKnowledgeCardIDs: Set<UUID>
    let savedKnowledgeCardIDs: Set<UUID>
    let showActions: Bool
    let billingEstimate: ChatBillingEstimate?
    @ObservedObject var memberContextStore: MemberContextStore
    let knowledgeDependencies: KnowledgeFeatureDependencies
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel

    let onRetry: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onToggleSpeech: () -> Void
    let onToggleTranslate: () -> Void
    let onOpenNetworkSearch: () -> Void
    let onSaveMessageToKnowledge: () -> Void
    let onGenerateKnowledgeCardsPreview: () -> Void
    let onSaveKnowledgeCard: (ChatKnowledgeCard) -> Void
    let onKnowledgeCardSaved: (ChatKnowledgeCard) -> Void
    let onTaskCardAction: (TaskCard.Action) -> Void
    let onPendingMemberToolSelect: (PendingMemberToolCard, Int?) -> Void
    let onToolQuestionCardSubmit: (ChatToolQuestionCard, [ToolQuestionResponse]) -> Void
    let onToolMemberSelectionCardSubmit: (ChatToolMemberSelectionCard, Int) -> Void
    let onHealthResourceCandidateCardChoose: (ChatHealthResourceCandidateSelectionCard) -> Void
    let onHealthResourceCandidateCardSkip: (ChatHealthResourceCandidateSelectionCard) -> Void
    let onToolConsentCardAllow: (ChatToolConsentCard) -> Void
    let onToolConsentCardDeny: (ChatToolConsentCard) -> Void
    let onToolConsentCardShowDetails: (ChatToolConsentCard) -> Void
    let savingStructuredHealthCardIDs: Set<UUID>
    let savingNutritionCardIDs: Set<UUID>
    let onStructuredHealthCardAction: (ChatStructuredHealthCardAction) -> Void
    let onNutritionCardAction: (ChatNutritionCardAction) -> Void
    let onCaptureOpenCamera: () -> Void
    let onCaptureOpenPhotoLibrary: () -> Void
    let onCaptureOpenFiles: () -> Void
    let onPresentToolPreview: (ToolPreviewPrompt, ChatRenderContext) -> Void
    let fileTransferService: FileTransferService
    let medicalQueryAPI: SparkMedicalQueryAPI
    let cachedMemberCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let onHealthResourceUnavailableTap: () -> Void
    let healthResourceDestinationFactory: (HealthResourceReference) -> AnyView
    let onHeightChangingUpdate: (@escaping () -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if shouldUseBodyFocusedLayout {
                if chatToolTracePayload.rows.isEmpty == false {
                    ChatToolTraceDisclosureView(
                        payload: chatToolTracePayload,
                        displayMode: toolTraceDisplayMode,
                        collapseToolsWhileStreaming: collapseToolsWhileStreaming
                    ) {
                        ForEach(chatToolTraceTimelineNodes) { node in
                            node.render(context: renderContext)
                        }
                    }
                }

                ForEach(bodyFocusedTimelineNodes) { node in
                    node.render(context: renderContext)
                }
            } else {
                ForEach(effectiveTimeline) { node in
                    node.render(context: renderContext)
                }
            }
            billingFooter
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var renderContext: ChatRenderContext {
        ChatRenderContext(
            message: message,
            isLastAssistantMessage: isLastAssistantMessage,
            isMathMode: isMathMode,
            conversationCardStyle: conversationCardStyle,
            toolTraceDisplayMode: toolTraceDisplayMode,
            collapseToolsWhileStreaming: collapseToolsWhileStreaming,
            taskCardLoadingIDs: taskCardLoadingIDs,
            savingKnowledgeCardIDs: savingKnowledgeCardIDs,
            savedKnowledgeCardIDs: savedKnowledgeCardIDs,
            savingStructuredHealthCardIDs: savingStructuredHealthCardIDs,
            savingNutritionCardIDs: savingNutritionCardIDs,
            memberContextStore: memberContextStore,
            knowledgeDependencies: knowledgeDependencies,
            knowledgeViewModel: knowledgeViewModel,
            errorCardBodyText: errorCardBodyText,
            onRetry: onRetry,
            onSaveKnowledgeCard: onSaveKnowledgeCard,
            onKnowledgeCardSaved: onKnowledgeCardSaved,
            onTaskCardAction: onTaskCardAction,
            onPendingMemberToolSelect: onPendingMemberToolSelect,
            onToolQuestionCardSubmit: onToolQuestionCardSubmit,
            onToolMemberSelectionCardSubmit: onToolMemberSelectionCardSubmit,
            onHealthResourceCandidateCardChoose: onHealthResourceCandidateCardChoose,
            onHealthResourceCandidateCardSkip: onHealthResourceCandidateCardSkip,
            onToolConsentCardAllow: onToolConsentCardAllow,
            onToolConsentCardDeny: onToolConsentCardDeny,
            onToolConsentCardShowDetails: onToolConsentCardShowDetails,
            onStructuredHealthCardAction: onStructuredHealthCardAction,
            onNutritionCardAction: onNutritionCardAction,
            onCaptureOpenCamera: onCaptureOpenCamera,
            onCaptureOpenPhotoLibrary: onCaptureOpenPhotoLibrary,
            onCaptureOpenFiles: onCaptureOpenFiles,
            onPresentToolPreview: onPresentToolPreview,
            fileTransferService: fileTransferService,
            medicalQueryAPI: medicalQueryAPI,
            cachedMemberCompleteData: cachedMemberCompleteData,
            healthResourceReferenceCount: healthResourceReferenceCount,
            onHealthResourceUnavailableTap: onHealthResourceUnavailableTap,
            healthResourceDestinationFactory: healthResourceDestinationFactory,
            onHeightChangingUpdate: onHeightChangingUpdate
        )
    }

    private var healthResourceReferenceCount: Int {
        message.blocks.filter { $0.kind == .healthResourceReference }.count
    }

    private var effectiveBlocks: [ChatMessageBlock] {
        var blocks = message.blocks

        if let translatedText, translatedText.isEmpty == false {
            blocks.removeAll { $0.kind == .translatedText }
            blocks.append(ChatMessageBlock(kind: .translatedText, text: translatedText, createdAt: message.createdAt, updatedAt: message.createdAt))
        }

        return blocks
    }

    private var effectiveTimeline: [ChatMessageTimelineNode] {
        ChatMessageTimelineProjector.project(blocks: effectiveBlocks, messageRole: message.role)
    }

    private var shouldUseBodyFocusedLayout: Bool {
        message.role != .user && conversationCardStyle == .bodyFocused
    }

    private var chatToolTraceBlocks: [ChatMessageBlock] {
        effectiveTimeline.flatMap { node in
            switch node.content {
            case .block(let block) where block.kind == .deepThought:
                return [block]
            case .tool(let toolNode):
                let toolBlocks = [toolNode.toolBlock].compactMap { $0 }
                if separatesToolPresentationsInBodyFocused {
                    return toolBlocks
                }
                return toolBlocks + toolNode.presentations
            default:
                return []
            }
        }
    }

    private var chatToolTraceTimelineNodes: [ChatMessageTimelineNode] {
        if separatesToolPresentationsInBodyFocused == false {
            return effectiveTimeline.filter { node in
                switch node.content {
                case .block(let block):
                    return block.kind == .deepThought
                case .tool:
                    return true
                case .healthResourceReferenceGroup:
                    return false
                }
            }
        }

        return effectiveTimeline.compactMap { node in
            switch node.content {
            case .block(let block):
                return block.kind == .deepThought ? node : nil
            case .tool(let toolNode):
                guard toolNode.toolBlock != nil else { return nil }
                let traceOnlyNode = ChatToolTimelineNode(
                    id: toolNode.id,
                    toolCallID: toolNode.toolCallID,
                    toolBlock: toolNode.toolBlock,
                    presentations: []
                )
                return ChatMessageTimelineNode(id: node.id, content: .tool(traceOnlyNode))
            case .healthResourceReferenceGroup:
                return nil
            }
        }
    }

    private var bodyFocusedTimelineNodes: [ChatMessageTimelineNode] {
        if separatesToolPresentationsInBodyFocused == false {
            return effectiveTimeline.filter { node in
                switch node.content {
                case .block(let block):
                    return block.kind != .deepThought
                case .tool:
                    return false
                case .healthResourceReferenceGroup:
                    return true
                }
            }
        }

        let nodes = effectiveTimeline.flatMap { node -> [ChatMessageTimelineNode] in
            switch node.content {
            case .block(let block):
                return block.kind == .deepThought ? [] : [node]
            case .tool(let toolNode):
                return toolNode.presentations.map { presentation in
                    ChatMessageTimelineNode(id: presentation.id, content: .block(presentation))
                }
            case .healthResourceReferenceGroup:
                return [node]
            }
        }
        return nodes.isEmpty ? effectiveTimeline : nodes
    }

    private var chatToolTracePayload: ChatToolTracePresentationModel {
        ChatToolTracePresentationModel(
            message: message,
            blocks: chatToolTraceBlocks,
            metadata: metadata
        )
    }

    var actionButtonsHStack: some View {
        
        HStack(spacing: 10) {
            Button(action: onCopy) {
                Image(systemName: "square.on.square")
            }
            .font(.caption)
            
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .font(.caption)
            
            if message.role == .assistant {
                Button(action: onToggleSpeech) {
                    Image(systemName: isSpeaking ? "pause.circle" : "waveform")
                }
                .font(.caption)
                
                Button(action: onToggleTranslate) {
                    if isTranslating {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: translatedText?.isEmpty == false ? "trash" : "globe")
                    }
                }
                .font(.caption)
                
                Button(action: onOpenNetworkSearch) {
                    Image(systemName: "network")
                }
                .font(.caption)
                
                Button(action: onSaveMessageToKnowledge) {
                    if isSavingMessage {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: isSavedMessage ? "checkmark.circle.fill" : "square.and.arrow.down")
                    }
                }
                .font(.caption)
                
                Button(action: onGenerateKnowledgeCardsPreview) {
                    Image(systemName: combinedKnowledgeCards.isEmpty ? "backpack" : "backpack.fill")
                }
                .font(.caption)
            }
        }
        .foregroundStyle(.secondary)
        
    }

    @ViewBuilder
    private var billingFooter: some View {
        if let billingEstimate {
            HStack(spacing: 5) {
                Image(systemName: "creditcard")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
                Text(billingEstimate.displayText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.top, 2)
            .accessibilityLabel(billingEstimate.displayText)
        }
    }

    private var shouldRenderErrorCard: Bool {
        message.deliveryState == .failed && message.role != .user
    }

    private var errorCardBodyText: String {
        let trimmed = message.blocks
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            return trimmed
        }
        if let description = metadata.operationalDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           description.isEmpty == false {
            return description
        }
        return L10n.text("chat.error_card.generic_body")
    }

    private var operationalMeta: (state: String, description: String)? {
        guard message.deliveryState == .sending else { return nil }
        guard let toolBlock = message.blocks.last(where: { $0.kind == .tool }) else {
            let storedState = metadata.operationalState?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let storedDesc = metadata.operationalDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard storedState.isEmpty == false || storedDesc.isEmpty == false else { return nil }
            return (storedState, storedDesc)
        }

        let toolName = toolBlock.toolName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolContent = toolBlock.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let meta = ChatToolRuntimeAttachmentBuilder.makeOperationalMeta(
            toolName: toolName,
            toolContent: toolContent
        ) {
            return meta
        }

        let displayName = ChatToolRuntimeAttachmentBuilder.localizedDisplayName(for: toolName)
        let fallbackState = L10n.text("chat.bubble.tool.operating_prefix", fallback: "Using tool: ") + displayName
        return (fallbackState, "")
    }

}

struct ChatSmallTaskMessageCard: View {
    let payload: ChatSmallTaskMessageCardPayload

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: payload.displayIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.18)))

            VStack(alignment: .leading, spacing: 4) {
                Text(payload.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if payload.displayBrief.isEmpty == false {
                    Text(payload.displayBrief)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }
}

private struct ChatMessageTimelineNode: Identifiable {
    enum Content {
        case block(ChatMessageBlock)
        case tool(ChatToolTimelineNode)
        case healthResourceReferenceGroup([ChatHealthResourceReferencePayload])
    }

    let id: UUID
    let content: Content

    @ViewBuilder
    func render(context: ChatRenderContext) -> some View {
        switch content {
        case .block(let block):
            block.render(context: context)
        case .tool(let node):
            ChatToolTimelineNodeView(node: node, context: context)
        case .healthResourceReferenceGroup(let payloads):
            ChatHealthResourceReferenceGroupBlockView(
                payloads: payloads,
                medicalQueryAPI: context.medicalQueryAPI,
                cachedCompleteData: context.cachedMemberCompleteData,
                onUnavailableTap: context.onHealthResourceUnavailableTap,
                destinationBuilder: context.healthResourceDestinationFactory
            )
        }
    }
}

private struct ChatToolTimelineNode: Identifiable {
    let id: UUID
    let toolCallID: String
    var toolBlock: ChatMessageBlock?
    var presentations: [ChatMessageBlock]
}

private enum ChatMessageTimelineProjector {
    nonisolated static func project(
        blocks: [ChatMessageBlock],
        messageRole: ChatMessageRole
    ) -> [ChatMessageTimelineNode] {
        var nodes: [ChatMessageTimelineNode] = []
        var toolNodeIndexByCallID: [String: Int] = [:]
        let sortedBlocks = blocks.sorted(by: sortBlocks)
        var index = 0

        while index < sortedBlocks.count {
            let block = sortedBlocks[index]

            if messageRole == .user,
               block.kind == .healthResourceReference,
               let payload = healthResourcePayload(from: block) {
                var payloads = [payload]
                var groupBlockIDs = [block.id]
                var next = index + 1
                while next < sortedBlocks.count,
                      sortedBlocks[next].kind == .healthResourceReference,
                      let nextPayload = healthResourcePayload(from: sortedBlocks[next]) {
                    payloads.append(nextPayload)
                    groupBlockIDs.append(sortedBlocks[next].id)
                    next += 1
                }
                let groupID = groupBlockIDs.first ?? block.id
                nodes.append(
                    ChatMessageTimelineNode(
                        id: groupID,
                        content: .healthResourceReferenceGroup(payloads)
                    )
                )
                index = next
                continue
            }

            if block.nodeRole == .tool, let toolCallID = normalizedToolCallID(block.toolCallID) {
                let toolNodeIndex = ensureToolNode(
                    toolCallID: toolCallID,
                    toolBlock: block,
                    nodes: &nodes,
                    indexByCallID: &toolNodeIndexByCallID
                )
                if case .tool(var node) = nodes[toolNodeIndex].content {
                    node.toolBlock = block
                    nodes[toolNodeIndex] = ChatMessageTimelineNode(id: node.id, content: .tool(node))
                }
                index += 1
                continue
            }

            if block.nodeRole == .toolPresentation,
               let toolCallID = normalizedToolCallID(block.parentToolCallID ?? block.toolCallID) {
                let toolNodeIndex = ensureToolNode(
                    toolCallID: toolCallID,
                    toolBlock: nil,
                    nodes: &nodes,
                    indexByCallID: &toolNodeIndexByCallID
                )
                if case .tool(var node) = nodes[toolNodeIndex].content,
                   node.presentations.contains(where: { $0.id == block.id }) == false {
                    node.presentations.append(block)
                    node.presentations.sort(by: sortBlocks)
                    nodes[toolNodeIndex] = ChatMessageTimelineNode(id: node.id, content: .tool(node))
                }
                index += 1
                continue
            }

            nodes.append(ChatMessageTimelineNode(id: block.id, content: .block(block)))
            index += 1
        }

        return nodes
    }

    nonisolated private static func healthResourcePayload(from block: ChatMessageBlock) -> ChatHealthResourceReferencePayload? {
        guard block.kind == .healthResourceReference else { return nil }
        if case .healthResourceReference(let payload) = block.payload {
            return payload
        }
        return nil
    }

    nonisolated private static func ensureToolNode(
        toolCallID: String,
        toolBlock: ChatMessageBlock?,
        nodes: inout [ChatMessageTimelineNode],
        indexByCallID: inout [String: Int]
    ) -> Int {
        if let index = indexByCallID[toolCallID] {
            return index
        }
        let placeholderMessageID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        let id = toolBlock?.id ?? ChatStableBlockID.tool(messageID: placeholderMessageID, toolCallID: toolCallID)
        let node = ChatToolTimelineNode(
            id: id,
            toolCallID: toolCallID,
            toolBlock: toolBlock,
            presentations: []
        )
        let index = nodes.count
        nodes.append(ChatMessageTimelineNode(id: id, content: .tool(node)))
        indexByCallID[toolCallID] = index
        return index
    }

    nonisolated private static func normalizedToolCallID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    nonisolated private static func sortBlocks(_ lhs: ChatMessageBlock, _ rhs: ChatMessageBlock) -> Bool {
        switch (lhs.orderKey, rhs.orderKey) {
        case let (l?, r?) where l != r:
            return l < r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.createdAt < rhs.createdAt
        }
    }

    nonisolated private static func isToolPresentationBlock(_ kind: ChatMessageBlockKind) -> Bool {
        switch kind {
        case .tool, .text, .deepThought, .error, .assistantStatusCard:
            return false
        case .imageGallery,
                .fileAttachments,
                .knowledgeCards,
                .translatedText,
                .mapRoute,
                .events,
                .healthCards,
                .pendingMemberToolCards,
                .toolQuestionCards,
                .toolMemberSelectionCards,
                .healthResourceCandidateCards,
                .toolConsentCards,
                .structuredHealthCards,
                .sleepVisualization,
                .nutritionCards,
                .medicalRiskNotice,
                .workoutVisualization,
                .captureCard,
                .html,
                .smallTaskCard,
                .taskCards,
                .healthResourceReference:
            return true
        case .medicalDisclaimerCard:
            return false
        }
    }
}

private struct ChatToolTimelineNodeView: View {
    let node: ChatToolTimelineNode
    let context: ChatRenderContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if node.presentations.isEmpty {
                if let toolBlock = node.toolBlock {
                    toolBlock.render(context: context)
                } else {
                    ChatToolTimelinePendingView(title: "正在整理结构化数据...")
                }
            } else {
                if let toolBlock = node.toolBlock {
                    toolBlock.render(context: context)
                }
                ForEach(node.presentations) { presentation in
                    switch presentation.status {
                    case .pending, .streaming:
                        ChatToolTimelinePendingView(title: pendingTitle(for: presentation.kind))
                    case .failed, .ready:
                        presentation.render(context: context)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pendingTitle(for kind: ChatMessageBlockKind) -> String {
        switch kind {
        case .structuredHealthCards:
            return "正在结构化健康数据..."
        case .sleepVisualization:
            return "正在生成睡眠可视化..."
        case .nutritionCards:
            return "正在生成营养卡片..."
        case .medicalRiskNotice:
            return "正在生成医疗风险提示..."
        case .workoutVisualization:
            return "正在生成运动可视化..."
        case .knowledgeCards:
            return "正在整理知识卡片..."
        case .taskCards, .smallTaskCard:
            return "正在创建提醒..."
        case .captureCard:
            return "正在准备采集卡片..."
        case .toolQuestionCards:
            return "等待用户回答..."
        case .toolMemberSelectionCards, .pendingMemberToolCards:
            return "等待选择成员..."
        case .healthResourceCandidateCards:
            return "等待选择健康资料..."
        case .toolConsentCards:
            return "等待数据授权..."
        default:
            return "正在整理结果..."
        }
    }
}

private struct ChatToolTimelinePendingView: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(title)
    }
}

struct ChatAssistantStatusCardView: View {
    let type: ChatAssistantStatusCardType
    let message: String
    let onRetry: () -> Void

    private var title: String {
        switch type {
        case .interrupted:
            return L10n.text("chat.status_card.interrupted.title")
        case .sendFailed:
            return L10n.text("chat.error_card.title")
        }
    }

    private var retryTitle: String {
        L10n.text("chat.error_card.retry")
    }

    private var systemImage: String {
        switch type {
        case .interrupted:
            return "stop.circle.fill"
        case .sendFailed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch type {
        case .interrupted:
            return .secondary
        case .sendFailed:
            return .orange
        }
    }

    private var showsRetry: Bool {
        switch type {
        case .interrupted:
            return false
        case .sendFailed:
            return true
        }
    }

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if showsRetry {
                Button(action: onRetry) {
                    Label(retryTitle, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
        }
        .padding(14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }

    var body: some View {
        bodyView
    }
}

typealias ChatMessageErrorCard = ChatAssistantStatusCardView

private struct ChatToolTracePresentationModel {
    let title: String
    let rows: [ChatToolTraceRowModel]
    let isStreaming: Bool
    let isFinalAnswerPhase: Bool
    let elapsedSeconds: Double?

    init(message: ChatMessage, blocks: [ChatMessageBlock], metadata: ChatMessageMetadata) {
        rows = blocks.map(ChatToolTraceRowModel.init(block:))
        isStreaming = message.deliveryState == .sending
        let hasText = message.blocks.contains { block in
            guard block.kind == .text else { return false }
            return block.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        isFinalAnswerPhase = message.deliveryState != .sending || hasText
        elapsedSeconds = Self.estimatedDuration(from: blocks)

        let hasFailure = rows.contains { $0.status == .failed }
        if isStreaming {
            title = rows.contains(where: { $0.status == .running }) ? "调用工具中…" : "AI 思考中…"
        } else if hasFailure || message.deliveryState == .failed {
            title = "失败"
        } else {
            title = "已完成"
        }

        _ = metadata
    }

    var toolCallCount: Int {
        rows.filter { $0.kind == .tool }.count
    }

    var durationText: String? {
        guard let elapsedSeconds, elapsedSeconds > 0 else { return nil }
        let total = Int(elapsedSeconds.rounded())
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private static func estimatedDuration(from blocks: [ChatMessageBlock]) -> Double? {
        guard blocks.isEmpty == false else { return nil }
        let earliest = blocks.map(\.createdAt).min()
        let latest = blocks.map(\.updatedAt).max()
        if let earliest, let latest {
            let measured = latest.timeIntervalSince(earliest)
            if measured > 0.5 {
                return measured
            }
        }
        return max(1, Double(blocks.count) * 0.4)
    }
}

private struct ChatToolTraceRowModel: Identifiable {
    enum Kind {
        case thinking
        case tool
    }

    enum Status {
        case running
        case completed
        case failed
    }

    let id: UUID
    let kind: Kind
    let title: String
    let chip: String?
    let status: Status

    init(block: ChatMessageBlock) {
        id = block.id
        switch block.payload {
        case .deepThought(let card):
            kind = .thinking
            title = "AI 思考"
            chip = card.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines)
            status = block.status == .streaming ? .running : .completed
        case .tool(let tool):
            kind = .tool
            title = ChatToolRuntimeAttachmentBuilder.localizedDisplayName(for: tool.name)
            if let meta = ChatToolRuntimeAttachmentBuilder.makeOperationalMeta(
                toolName: tool.name,
                toolContent: tool.content
            ) {
                chip = meta.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : meta.description
            } else {
                chip = tool.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : tool.content
            }
            switch block.status {
            case .pending, .streaming:
                status = .running
            case .failed:
                status = .failed
            default:
                status = .completed
            }
        default:
            kind = .tool
            title = "工具调用"
            chip = block.text
            status = block.status == .failed ? .failed : .completed
        }
    }
}

private struct ChatToolTraceDisclosureView<Content: View>: View {
    let payload: ChatToolTracePresentationModel
    let displayMode: ChatToolTraceDisplayMode
    let collapseToolsWhileStreaming: Bool
    let content: () -> Content
    @State private var userPinnedExpansion: Bool?

    init(
        payload: ChatToolTracePresentationModel,
        displayMode: ChatToolTraceDisplayMode,
        collapseToolsWhileStreaming: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.payload = payload
        self.displayMode = displayMode
        self.collapseToolsWhileStreaming = collapseToolsWhileStreaming
        self.content = content
    }

    private var effectiveExpanded: Bool {
        if let userPinnedExpansion { return userPinnedExpansion }
        switch displayMode {
        case .expanded:
            return true
        case .collapsedAlways:
            return false
        case .collapsedAfterCompletion:
            if payload.isStreaming && collapseToolsWhileStreaming == false {
                return true
            }
            return !payload.isFinalAnswerPhase
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if effectiveExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    content()
                }
                .padding(.leading, 12)
                .padding(.top, 8)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.35))
                        .frame(width: 1)
                }
                .padding(.leading, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) {
                userPinnedExpansion = !effectiveExpanded
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: payload.isStreaming ? "sparkles" : "checkmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.85))

                Text(payload.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                if let durationText = payload.durationText {
                    Text("· \(durationText)")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary.opacity(0.6))
                }

                if payload.toolCallCount > 0 {
                    Text("· \(payload.toolCallCount) 次调用")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.6))
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .rotationEffect(.degrees(effectiveExpanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("工具调用")
        .accessibilityValue(effectiveExpanded ? "已展开" : "已折叠")
    }
}
