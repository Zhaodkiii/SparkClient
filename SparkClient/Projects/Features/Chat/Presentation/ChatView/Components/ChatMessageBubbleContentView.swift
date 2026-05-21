import SwiftUI
import UIKit

/// 单条消息气泡内容：
/// - 纯渲染组件，不直接持有全局状态；
/// - 通过入参和回调与上层协作。
struct ChatMessageBubbleContentView: View {
    @State private var unifiedFilePreview: FilePreviewInput?

    let message: ChatMessage
    let metadata: ChatMessageMetadata
    let isLastAssistantMessage: Bool
    let translatedText: String?
    let combinedKnowledgeCards: [ChatKnowledgeCard]
    let isMathMode: Bool
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
    @ObservedObject var memberContextStore: MemberContextStore

    let onRetry: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onToggleSpeech: () -> Void
    let onToggleTranslate: () -> Void
    let onOpenNetworkSearch: () -> Void
    let onSaveMessageToKnowledge: () -> Void
    let onGenerateKnowledgeCardsPreview: () -> Void
    let onSaveKnowledgeCard: (ChatKnowledgeCard) -> Void
    let onTaskCardAction: (TaskCard.Action) -> Void
    let onPendingMemberToolSelect: (PendingMemberToolCard, Int?) -> Void
    let savingStructuredHealthCardIDs: Set<UUID>
    let onStructuredHealthCardAction: (ChatStructuredHealthCardAction) -> Void
    let onCaptureOpenCamera: () -> Void
    let onCaptureOpenPhotoLibrary: () -> Void
    let onCaptureOpenFiles: () -> Void
    let onPresentToolPreview: (ToolPreviewPrompt, ChatRenderContext) -> Void
    let fileTransferService: FileTransferService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(effectiveTimeline) { node in
                node.render(context: renderContext)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(message.role == .user ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
        )
        .unifiedFilePreview(selection: $unifiedFilePreview)
    }

    private var renderContext: ChatRenderContext {
        ChatRenderContext(
            message: message,
            isLastAssistantMessage: isLastAssistantMessage,
            isMathMode: isMathMode,
            taskCardLoadingIDs: taskCardLoadingIDs,
            savingKnowledgeCardIDs: savingKnowledgeCardIDs,
            savedKnowledgeCardIDs: savedKnowledgeCardIDs,
            savingStructuredHealthCardIDs: savingStructuredHealthCardIDs,
            memberContextStore: memberContextStore,
            unifiedFilePreview: $unifiedFilePreview,
            errorCardBodyText: errorCardBodyText,
            onRetry: onRetry,
            onSaveKnowledgeCard: onSaveKnowledgeCard,
            onTaskCardAction: onTaskCardAction,
            onPendingMemberToolSelect: onPendingMemberToolSelect,
            onStructuredHealthCardAction: onStructuredHealthCardAction,
            onCaptureOpenCamera: onCaptureOpenCamera,
            onCaptureOpenPhotoLibrary: onCaptureOpenPhotoLibrary,
            onCaptureOpenFiles: onCaptureOpenFiles,
            onPresentToolPreview: onPresentToolPreview,
            fileTransferService: fileTransferService
        )
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
        ChatMessageTimelineProjector.project(blocks: effectiveBlocks)
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
    nonisolated static func project(blocks: [ChatMessageBlock]) -> [ChatMessageTimelineNode] {
        var nodes: [ChatMessageTimelineNode] = []
        var toolNodeIndexByCallID: [String: Int] = [:]
        let sortedBlocks = blocks.sorted(by: sortBlocks)

        for block in sortedBlocks {
            if block.nodeRole == .tool, let toolCallID = normalizedToolCallID(block.toolCallID) {
                let index = ensureToolNode(
                    toolCallID: toolCallID,
                    toolBlock: block,
                    nodes: &nodes,
                    indexByCallID: &toolNodeIndexByCallID
                )
                if case .tool(var node) = nodes[index].content {
                    node.toolBlock = block
                    nodes[index] = ChatMessageTimelineNode(id: node.id, content: .tool(node))
                }
                continue
            }

            if block.nodeRole == .toolPresentation,
               let toolCallID = normalizedToolCallID(block.parentToolCallID ?? block.toolCallID) {
                let index = ensureToolNode(
                    toolCallID: toolCallID,
                    toolBlock: nil,
                    nodes: &nodes,
                    indexByCallID: &toolNodeIndexByCallID
                )
                if case .tool(var node) = nodes[index].content,
                   node.presentations.contains(where: { $0.id == block.id }) == false {
                    node.presentations.append(block)
                    node.presentations.sort(by: sortBlocks)
                    nodes[index] = ChatMessageTimelineNode(id: node.id, content: .tool(node))
                }
                continue
            }

            nodes.append(ChatMessageTimelineNode(id: block.id, content: .block(block)))
        }

        return nodes
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
        case .tool, .text, .deepThought, .error:
            return false
        case .imageGallery,
                .fileAttachments,
                .knowledgeCards,
                .translatedText,
                .mapRoute,
                .events,
                .healthCards,
                .pendingMemberToolCards,
                .structuredHealthCards,
                .sleepVisualization,
                .workoutVisualization,
                .captureCard,
                .html,
                .smallTaskCard,
                .taskCards:
            return true
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
        case .workoutVisualization:
            return "正在生成运动可视化..."
        case .knowledgeCards:
            return "正在整理知识卡片..."
        case .taskCards, .smallTaskCard:
            return "正在创建提醒..."
        case .captureCard:
            return "正在准备采集卡片..."
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

struct ChatMessageErrorCard: View {
    let title: String
    let message: String
    let retryTitle: String
    let onRetry: () -> Void

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRetry) {
                Label(retryTitle, systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(14)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    var body: some View {
        bodyView
    }
}
