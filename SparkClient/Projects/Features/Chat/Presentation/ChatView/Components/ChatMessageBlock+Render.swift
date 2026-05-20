import SwiftUI

// MARK: - 聊天消息块 渲染扩展
/// 根据消息块的不同类型，渲染对应的UI组件（错误、图片、思考、工具、卡片、文件、文本等）
extension ChatMessageBlock {
    
    /// 渲染消息块UI入口
    /// - Parameter context: 渲染上下文（携带消息、样式、回调等数据）
    /// - Returns: 不同类型对应的视图组件
    @ViewBuilder
    func render(context: ChatRenderContext) -> some View {
        if status == .pending || (status == .streaming && kind != .text && kind != .deepThought && kind != .tool) {
            ChatPendingPresentationBlockView(title: pendingPresentationTitle)
        } else {
        // 根据消息块类型分发到不同UI
        switch payload {
            
            // 1. 错误提示卡片
        case .error(let message):
            ChatMessageErrorCard(
                title: L10n.text("chat.error_card.title"),
                message: message.isEmpty ? context.errorCardBodyText : message,
                retryTitle: L10n.text("chat.error_card.retry"),
                onRetry: context.onRetry
            )
            
            // 2. 图片画廊（多图展示）
        case .imageGallery(let attachments):
            ChatImageGalleryBlockView(
                images: ChatImagePayloadBuilder.imagePayloads(
                    from: imageGalleryMessage(attachments, base: context.message)
                ),
                style: context.message.role == .user ? .user : .assistant, // 用户/助手样式
                unifiedFilePreview: context.unifiedFilePreview,
                downloadToLocalFile: context.onDownloadChatAttachmentToLocalFile
            )
            
            // 3. 深度思考块（AI思考过程）
        case .deepThought(let card):
            ChatReasoningBlockView(
                text: card.reasoningContent ?? "",
                timeText: formatDeepThoughtDuration(card.reasoningDurationMs),
                isStreaming: context.message.deliveryState == .sending, // 是否正在流式输出
                isLastAssistantMessage: context.isLastAssistantMessage
            )
            
            // 4. 工具调用块（联网、文件、插件等）
        case .tool(let tool):
            ChatToolBlockStreamedPresentationView(
                toolBlock: self,
                context: context,
                tool: tool,
                wantsResult: shouldShowToolResultContent(context: context, tool: tool)
            )
            
            // 5. 知识库卡片列表
        case .knowledgeCards(let cards):
            ChatKnowledgeCardListView(
                cards: cards,
                onSave: context.onSaveKnowledgeCard,
                isSaving: { context.savingKnowledgeCardIDs.contains($0.id) },
                isSaved: { context.savedKnowledgeCardIDs.contains($0.id) }
            )
            
            // 6. 翻译文本块
        case .translatedText(let text):
            ChatTranslatedBlockView(text: text)
            
            // 7. 地图路线块
        case .mapRoute(let route):
            ChatMapRouteBlockView(locations: route.locations, routes: route.routes)
            
            // 8. 日程/事件卡片
        case .events(let events):
            ChatEventsCardListView(events: events)
            
            // 9. 健康数据卡片
        case .healthCards(let cards):
            ChatHealthCardListView(cards: cards)
            
            // 10. 等待用户选择成员的工具卡片
        case .pendingMemberToolCards(let cards):
            ForEach(cards) { card in
                ChatPendingMemberToolCardView(
                    card: card,
                    memberContextStore: context.memberContextStore,
                    onSelectMember: context.onPendingMemberToolSelect
                )
            }
            
            // 11. 结构化健康卡片
        case .structuredHealthCards(let blob):
            ChatStructuredHealthCardsBlockView(
                blob: blob,
                memberContextStore: context.memberContextStore,
                isSavingIDs: context.savingStructuredHealthCardIDs,
                onAction: context.onStructuredHealthCardAction
            )
            
            // 12. 睡眠数据可视化
        case .sleepVisualization(let sleep):
            ChatSleepVisualizationMessageCard(model: sleep)

            // 13. 运动数据可视化
        case .workoutVisualization(let workout):
            ChatWorkoutVisualizationMessageCard(model: workout)
            
            // 14. 快捷捕获卡片（相机/相册/文件）
        case .captureCard(let captureCard):
            ChatCaptureTypeMessageCard(
                cardType: captureCard.cardType,
                onOpenCamera: context.onCaptureOpenCamera,
                onOpenPhotoLibrary: context.onCaptureOpenPhotoLibrary,
                onOpenFiles: context.onCaptureOpenFiles
            )
            
            // 15. HTML 内容预览
        case .html(let html):
            if html.isEmpty == false {
                ChatHTMLPreviewBlockView(htmlContent: html)
            }
            
            // 16. 小任务卡片
        case .smallTaskCard(let payload):
            ChatSmallTaskMessageCard(payload: payload)
            
            // 17. 文件附件块
        case .fileAttachments(let attachments):
            ChatFileAttachmentBlockView(
                unifiedFilePreview: context.unifiedFilePreview,
                attachments: attachments,
                role: context.message.role,
                cachedLocalURL: context.onCachedChatAttachmentLocalURL,
                downloadToLocalFile: context.onDownloadChatAttachmentToLocalFile
            )
            
            // 18. 纯文本 / Markdown / 数学公式
        case .text(let text):
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                if context.isMathMode {
                    // 数学模式：等宽文本
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // 普通模式：Markdown渲染
                    Markdown(text)
                        .markdownTheme(.chatBubble(
                            foreground: context.message.role == .user ? .white : .primary
                        ))
                }
            }
            
            // 19. 任务卡片列表
        case .taskCards(let cards):
            ForEach(cards) { card in
                TaskCardCell(
                    card: card,
                    memberContextStore: context.memberContextStore,
                    onAction: context.onTaskCardAction,
                    isLoading: context.taskCardLoadingIDs.contains(card.id)
                )
            }

        }
        }
    }
    
    /// 工具方法：生成只包含附件的空内容消息（用于图片组件）
    /// - Parameters:
    ///   - attachments: 附件列表
    ///   - base: 原始消息
    /// - Returns: 只带附件的新消息
    private func imageGalleryMessage(_ attachments: [ChatAttachment], base: ChatMessage) -> ChatMessage {
        let galleryBlock = ChatMessageBlock(
            kind: .imageGallery,
            attachments: attachments,
            createdAt: base.createdAt,
            updatedAt: Date()
        )
        return ChatMessage(
            threadID: base.threadID,
            role: base.role,
            blocks: [galleryBlock],
            deliveryState: base.deliveryState,
            modelName: base.modelName
        )
    }

    /// 在 `deliveryState == .sending` 时，若本工具行后已出现其它块，或 `toolContent` 中已带可展示结果，则视为该次工具调用已结束，应显示结果区。
    private func shouldShowToolResultContent(context: ChatRenderContext, tool: ChatToolBlockPayload) -> Bool {
        if context.message.deliveryState != .sending { return true }
        if let index = context.message.blocks.firstIndex(where: { $0.id == id }),
           index + 1 < context.message.blocks.count {
            return true
        }
        if let meta = ChatToolRuntimeAttachmentBuilder.makeOperationalMeta(
            toolName: tool.name,
            toolContent: tool.content
        ) {
            return meta.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        return false
    }

    private func formatDeepThoughtDuration(_ durationMs: Int64?) -> String? {
        guard let durationMs, durationMs > 0 else { return nil }
        let seconds = Double(durationMs) / 1_000
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remainSeconds = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%dm %.1fs", minutes, remainSeconds)
    }

    private var pendingPresentationTitle: String {
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

private struct ChatPendingPresentationBlockView: View {
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
