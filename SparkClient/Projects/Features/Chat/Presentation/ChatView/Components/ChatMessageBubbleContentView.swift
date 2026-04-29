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
    let onCachedChatAttachmentLocalURL: (ChatAttachment) async -> URL?
    let onDownloadChatAttachmentToLocalFile: (ChatAttachment) async throws -> URL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(effectiveBlocks) { block in
                block.render(context: renderContext)
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
            onCachedChatAttachmentLocalURL: onCachedChatAttachmentLocalURL,
            onDownloadChatAttachmentToLocalFile: onDownloadChatAttachmentToLocalFile
        )
    }

    /// 最终生效的消息块数组（动态计算：根据状态动态插入/移除/替换 UI 块）
    /// 作用：根据消息发送状态、错误、翻译、知识库等条件，返回最终要渲染的 blocks
    private var effectiveBlocks: [ChatMessageBlock] {
        // 1. 先拿到原始消息的所有块
        var blocks = message.blocks

        // 2. 如果消息发送失败 + 需要显示错误卡片 → 在最前面插入【错误提示块】
        if message.deliveryState == .failed, shouldRenderErrorCard {
            blocks.insert(
                ChatMessageBlock(kind: .error, text: errorCardBodyText, createdAt: message.createdAt, updatedAt: message.createdAt),
                at: 0
            )
        }

        // 3. 如果有合并后的知识库卡片 → 移除旧的知识卡片，追加新的
        if combinedKnowledgeCards.isEmpty == false {
            // 先删掉已有的知识卡片块
            blocks.removeAll { $0.kind == .knowledgeCards }
            // 追加最新合并后的知识卡片块
            blocks.append(ChatMessageBlock(kind: .knowledgeCards, knowledgeCards: combinedKnowledgeCards, createdAt: message.createdAt, updatedAt: message.createdAt))
        }

        // 4. 如果有翻译文本 → 移除旧翻译块，追加新翻译块
        if let translatedText, translatedText.isEmpty == false {
            // 先删掉已有的翻译块
            blocks.removeAll { $0.kind == .translatedText }
            // 追加最新翻译文本
            blocks.append(ChatMessageBlock(kind: .translatedText, text: translatedText, createdAt: message.createdAt, updatedAt: message.createdAt))
        }

        return blocks
        // 5. 过滤工具块（去重）：
        // 只保留【有 toolCallID 但没有对应展示块】的工具块，避免重复渲染
//        return blocks.filter { block in
//            // 非工具块直接保留
//            guard block.kind == .tool else { return true }
//            // 没有 toolCallID 的工具块直接保留
//            guard let toolCallID = block.toolCallID, !toolCallID.isEmpty else { return true }
//            // 如果已经有对应展示块了，就过滤掉这个原始工具块
//            return !blocks.contains(where: {
//                $0.toolCallID == toolCallID && Self.isToolPresentationBlock($0.kind)
//            })
//        }
    }

    private static func isToolPresentationBlock(_ kind: ChatMessageBlockKind) -> Bool {
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
                .captureCard,
                .html,
                .smallTaskCard,
                .taskCards:
            return true
        }
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
