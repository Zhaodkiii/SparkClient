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
        switch payload {
            
            // 1. 状态提示卡片
        case .error(let message):
            ChatAssistantStatusCardView(
                type: .sendFailed,
                message: message.isEmpty ? context.errorCardBodyText : message,
                onRetry: context.onRetry
            )
        case .assistantStatusCard(let card):
            ChatAssistantStatusCardView(
                type: card.type,
                message: card.message.isEmpty ? context.errorCardBodyText : card.message,
                onRetry: context.onRetry
            )
            
            // 2. 图片画廊（多图展示）
        case .imageGallery(let attachments):
            ChatImageGalleryBlockView(
                images: ChatImagePayloadBuilder.imagePayloads(
                    from: imageGalleryMessage(attachments, base: context.message)
                ),
                fileTransferService: context.fileTransferService,
                style: context.message.role == .user ? .user : .assistant
            )
            
            // 3. 深度思考块（AI思考过程）
        case .deepThought(let card):
            ChatReasoningBlockView(
                text: card.reasoningContent ?? "",
                timeText: formatDeepThoughtDuration(card.reasoningDurationMs),
                isStreaming: context.message.deliveryState == .sending, // 是否正在流式输出
                isLastAssistantMessage: context.isLastAssistantMessage,
                onHeightChangingUpdate: context.onHeightChangingUpdate
            )
            .id(id)
            
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
                knowledgeDependencies: context.knowledgeDependencies,
                knowledgeViewModel: context.knowledgeViewModel,
                onSave: context.onSaveKnowledgeCard,
                onSaved: context.onKnowledgeCardSaved,
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

        case .toolQuestionCards(let cards):
            ForEach(cards) { card in
                ChatToolQuestionMessageCardView(
                    card: card,
                    onSubmit: context.onToolQuestionCardSubmit
                )
            }

        case .toolMemberSelectionCards(let cards):
            ForEach(cards) { card in
                ChatToolMemberSelectionMessageCardView(
                    card: card,
                    memberContextStore: context.memberContextStore,
                    onSubmit: context.onToolMemberSelectionCardSubmit
                )
            }

        case .healthResourceCandidateCards(let cards):
            ForEach(cards) { card in
                ChatHealthResourceCandidateMessageCardView(
                    card: card,
                    onChoose: context.onHealthResourceCandidateCardChoose,
                    onSkip: context.onHealthResourceCandidateCardSkip
                )
            }

        case .toolConsentCards(let cards):
            ForEach(cards) { card in
                ChatToolConsentMessageCardView(
                    card: card,
                    onAllow: context.onToolConsentCardAllow,
                    onDeny: context.onToolConsentCardDeny,
                    onShowDetails: context.onToolConsentCardShowDetails
                )
            }
            
            // 11. 结构化健康卡片
        case .structuredHealthCards(let blob):
            ChatStructuredHealthCardsBlockView(
                blockID: id,
                blockStatus: status,
                blob: blob,
                memberContextStore: context.memberContextStore,
                isSavingIDs: context.savingStructuredHealthCardIDs,
                onOpenPreview: { item in
                    context.onStructuredHealthCardOpenPreview(id, item, context.message)
                },
                onAction: context.onStructuredHealthCardAction
            )
            
            // 12. 睡眠数据可视化
        case .sleepVisualization(let sleep):
            ChatSleepVisualizationMessageCard(model: sleep)

            // 12b. 营养卡片
        case .nutritionCards(let payload):
            ChatNutritionCardsBlockView(
                blockID: id,
                cards: payload.cards,
                savingCardIDs: context.savingNutritionCardIDs,
                onAction: context.onNutritionCardAction
            )

            // 13. 运动数据可视化
        case .workoutVisualization(let workout):
            ChatWorkoutVisualizationMessageCard(model: workout)
            
            // 14. 快捷捕获卡片（相机/相册/文件）
        case .captureCard(let captureCard):
            ChatCaptureTypeMessageCard(
                payload: captureCard,
                onAttachmentsPicked: { attachments in
                    context.onCaptureAttachmentsPicked(captureCard, attachments)
                },
                onCancel: {
                    context.onCaptureCancel(captureCard)
                }
            )
            
            // 15. HTML 内容预览
        case .html(let html):
            if html.isEmpty == false {
                ChatHTMLPreviewBlockView(htmlContent: html)
            }
            
            // 16. 小任务卡片
        case .smallTaskCard(let payload):
            ChatSmallTaskMessageCard(
                payload: payload,
                onOpen: context.onSmallTaskCardOpen
            )
            
            // 17. 文件附件块
        case .fileAttachments(let attachments):
            ChatFileAttachmentBlockView(
                attachments: attachments,
                role: context.message.role,
                fileTransferService: context.fileTransferService
            )
            
            // 18. 纯文本 / Markdown / 数学公式
        case .text(let text):
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                if context.isMathMode {
                    // 数学模式：等宽文本（文本选择由气泡长按菜单统一处理）
                    Text(text)
                        .font(.system(.body, design: .monospaced))
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
                    onOpenPreview: { selectedCard in
                        context.onTaskCardOpen(selectedCard, context.message)
                    },
                    onAction: context.onTaskCardAction,
                    isLoading: context.taskCardLoadingIDs.contains(card.id)
                )
            }

        case .healthResourceReference(let payload):
            // 用户消息在 Timeline 层已合并为 Group；此处仅渲染助手等非用户消息中的单卡。
            if context.message.role == .user {
                EmptyView()
            } else {
                ChatHealthResourceReferenceBlockView(
                    payload: payload,
                    totalRefs: max(1, context.healthResourceReferenceCount),
                    medicalQueryAPI: context.medicalQueryAPI,
                    cachedCompleteData: context.cachedMemberCompleteData,
                    onUnavailableTap: context.onHealthResourceUnavailableTap,
                    destinationBuilder: context.healthResourceDestinationFactory
                )
            }

        case .medicalRiskNotice(let payload):
            ChatMedicalRiskNoticeCardView(payload: payload)

        case .medicalDisclaimerCard(let payload):
            if context.message.deliveryState == .sending {
                EmptyView()
            } else {
                ChatMedicalDisclaimerCardView(payload: payload)
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
        case .nutritionCards:
            return "正在生成营养卡片..."
        case .medicalRiskNotice:
            return "正在生成医疗风险提示..."
        case .workoutVisualization:
            return "正在生成运动可视化..."
        case .healthResourceReference:
            return "正在加载健康资料…"
        case .knowledgeCards:
            return "正在整理知识卡片..."
        case .taskCards, .smallTaskCard:
            return "正在创建提醒..."
        case .captureCard:
            return "正在准备采集卡片..."
        case .toolQuestionCards:
            return "等待用户回答..."
        case .toolMemberSelectionCards:
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
