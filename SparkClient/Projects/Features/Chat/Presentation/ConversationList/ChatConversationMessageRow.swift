import SwiftUI
import UIKit

/// 单条会话消息行（从 ``ChatView`` 抽出），供 `UICollectionView` + `UIHostingController` 复用。
struct ChatConversationMessageRow: View {
    @State private var rowWidth: CGFloat = 0
    @State private var bubbleMenuConfig: ChatBubbleMenuConfig?
    @State private var textSelectionPayload: ChatSelectableTextPayload?

    let threadID: UUID
    let message: ChatMessage
    let visibleMessages: [ChatMessage]
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var detailViewModel: ChatDetailViewModel
    @ObservedObject var uiStateStore: ChatMessageUIStateStore
    @ObservedObject var speechHelper: ChatSpeechHelper
    @ObservedObject var memberContextStore: MemberContextStore
    let actionState: ChatMessageActionState
    let conversationAppearance: ChatConversationAppearancePreferences
    let taskManager: TaskManager
    let logger: Logger
    let onCaptureOpenFiles: () -> Void
    let onHeightChangingUpdate: (@escaping () -> Void) -> Void

    private var messageActionUseCase: any ChatMessageActionUseCase {
        DefaultChatMessageActionUseCase(taskManager: taskManager, logger: logger)
    }

    private var shouldUseUnifiedRetryFlow: Bool {
        message.clientMessageID == ChatView.inlineErrorClientMessageID || message.role != .user
    }

    private var bubbleMaxWidth: CGFloat {
        let rowHorizontalPadding: CGFloat = 16
        let oppositeSideMinimumMargin: CGFloat = message.role == .user ? 40 : 0
        let fallbackWidth = UIScreen.main.bounds.width
        let measuredWidth = rowWidth > 0 ? rowWidth : fallbackWidth
        return max(1, measuredWidth - rowHorizontalPadding - oppositeSideMinimumMargin)
    }

    var body: some View {
        HStack {
            if message.role == .assistant || message.role == .system {
                longPressableBubble
                    .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 40)
                longPressableBubble
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor)
                    )
                    .frame(maxWidth: bubbleMaxWidth, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(8)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: RowWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(RowWidthPreferenceKey.self) { width in
            if abs(rowWidth - width) > 0.5 {
                rowWidth = width
            }
        }
        .transparentFullScreenCover(
            isPresented: Binding(
                get: { bubbleMenuConfig != nil },
                set: { if !$0 { bubbleMenuConfig = nil } }
            )
        ) {
            if let config = bubbleMenuConfig {
                ChatBubbleMenuView(config: config) {
                    bubbleMenuConfig = nil
                }
            }
        }
        .sheet(item: $textSelectionPayload) { payload in
            NavigationStack {
                ChatTextSelectionView(
                    text: payload.text,
                    onSaveToKnowledge: message.role == .assistant
                        ? { saveMessageToKnowledge(message) }
                        : nil
                )
                .navigationTitle(payload.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(L10n.text("common.done")) {
                            textSelectionPayload = nil
                        }
                    }
                }
            }
        }
    }

    /// 带长按手势的气泡，替代系统 contextMenu
    private var longPressableBubble: some View {
        bubbleContent
            .contentShape(Rectangle())
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        bubbleMenuConfig = makeBubbleMenuConfig()
                    }
            )
    }

    private func makeBubbleMenuConfig() -> ChatBubbleMenuConfig {
        let metadata = ChatMessageMetadata(message: message)
        let isAssistant = message.role == .assistant
        let plain = messagePlainText(message)
        let hasText = plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return ChatBubbleMenuConfig(
            message: message,
            isAssistant: isAssistant,
            isSpeaking: speechHelper.isSpeaking(message.id),
            isTranslated: translatedText(for: message, metadata: metadata) != nil,
            plainText: plain,
            bubbleView: AnyView(previewBubble),
            hasSelectableText: hasText,
            onCopy: { UIPasteboard.general.string = plain },
            onSelectText: hasText ? {
                textSelectionPayload = ChatSelectableTextPayload(
                    title: L10n.text("chat.bubble.menu.select_text"),
                    text: plain
                )
            } : nil,
            onDelete: { uiStateStore.markDeleted(message.id) },
            onToggleSpeech: isAssistant
                ? { speechHelper.toggle(text: plain, id: message.id) }
                : nil,
            onToggleTranslate: isAssistant
                ? { toggleTranslate(message) }
                : nil,
            onSaveToKnowledge: isAssistant
                ? { saveMessageToKnowledge(message) }
                : nil
        )
    }

    /// 原始气泡的只读预览版：内容与 bubbleContent 完全一致，
    /// showActions=false 隐藏操作栏，allowsHitTesting=false 禁止交互。
    private var previewBubble: some View {
        let metadata = ChatMessageMetadata(message: message)
        return ChatMessageBubbleContentView(
            message: message,
            metadata: metadata,
            isLastAssistantMessage: false,
            translatedText: translatedText(for: message, metadata: metadata),
            combinedKnowledgeCards: combinedKnowledgeCards(for: message, metadata: metadata),
            isMathMode: uiStateStore.isMathMode(message.id),
            conversationCardStyle: conversationAppearance.cardStyle,
            toolTraceDisplayMode: conversationAppearance.toolTraceDisplayMode,
            collapseToolsWhileStreaming: conversationAppearance.collapseToolsWhileStreaming,
            isTranslating: false,
            isSavingMessage: false,
            isSavedMessage: false,
            isSpeaking: false,
            taskCardLoadingIDs: uiStateStore.taskCardLoadingIDs,
            ignoredTaskCardIDs: uiStateStore.ignoredTaskCardIDs,
            createdTaskCardIDs: uiStateStore.createdTaskCardIDs,
            savingKnowledgeCardIDs: [],
            savedKnowledgeCardIDs: uiStateStore.savedKnowledgeCardIDs,
            showActions: false,
            memberContextStore: memberContextStore,
            onRetry: {},
            onCopy: {},
            onDelete: {},
            onToggleSpeech: {},
            onToggleTranslate: {},
            onOpenNetworkSearch: {},
            onSaveMessageToKnowledge: {},
            onGenerateKnowledgeCardsPreview: {},
            onSaveKnowledgeCard: { _ in },
            onTaskCardAction: { _ in },
            onPendingMemberToolSelect: { _, _ in },
            onToolQuestionCardSubmit: { _, _ in },
            onToolMemberSelectionCardSubmit: { _, _ in },
            savingStructuredHealthCardIDs: [],
            savingNutritionCardIDs: [],
            onStructuredHealthCardAction: { _ in },
            onNutritionCardAction: { _ in },
            onCaptureOpenCamera: {},
            onCaptureOpenPhotoLibrary: {},
            onCaptureOpenFiles: {},
            onPresentToolPreview: { _, _ in },
            fileTransferService: detailViewModel.attachmentFileTransferService,
            medicalQueryAPI: detailViewModel.sparkMedicalQueryAPI,
            cachedMemberCompleteData: detailViewModel.cachedMemberCompleteData,
            onHealthResourceUnavailableTap: {},
            healthResourceDestinationFactory: { _ in AnyView(EmptyView()) },
            onHeightChangingUpdate: onHeightChangingUpdate
        )
        .allowsHitTesting(false)
    }

    private var bubbleContent: some View {
        let metadata = ChatMessageMetadata(message: message)
        return ChatMessageBubbleContentView(
            message: message,
            metadata: metadata,
            isLastAssistantMessage: isLastAssistantMessage(message),
            translatedText: translatedText(for: message, metadata: metadata),
            combinedKnowledgeCards: combinedKnowledgeCards(for: message, metadata: metadata),
            isMathMode: uiStateStore.isMathMode(message.id),
            conversationCardStyle: conversationAppearance.cardStyle,
            toolTraceDisplayMode: conversationAppearance.toolTraceDisplayMode,
            collapseToolsWhileStreaming: conversationAppearance.collapseToolsWhileStreaming,
            isTranslating: uiStateStore.isTranslating(message.id),
            isSavingMessage: uiStateStore.isMessageSaving(message.id),
            isSavedMessage: uiStateStore.isMessageSaved(message.id),
            isSpeaking: speechHelper.isSpeaking(message.id),
            taskCardLoadingIDs: uiStateStore.taskCardLoadingIDs,
            ignoredTaskCardIDs: uiStateStore.ignoredTaskCardIDs,
            createdTaskCardIDs: uiStateStore.createdTaskCardIDs,
            savingKnowledgeCardIDs: uiStateStore.savingKnowledgeCardIDs,
            savedKnowledgeCardIDs: uiStateStore.savedKnowledgeCardIDs,
            showActions: message.id == visibleMessages.last?.id,
            memberContextStore: memberContextStore,
            onRetry: {
                Task {
                    if shouldUseUnifiedRetryFlow {
                        await detailViewModel.retryLatestConversationFailure(
                            for: threadID,
                            preferredClientMessageID: message.clientMessageID == ChatView.inlineErrorClientMessageID ? nil : message.clientMessageID
                        )
                    } else {
                        await detailViewModel.retryFailedMessage(clientMessageID: message.clientMessageID)
                    }
                }
            },
            onCopy: {
                UIPasteboard.general.string = messagePlainText(message)
            },
            onDelete: {
                uiStateStore.markDeleted(message.id)
            },
            onToggleSpeech: {
                speechHelper.toggle(text: messagePlainText(message), id: message.id)
            },
            onToggleTranslate: {
                toggleTranslate(message)
            },
            onOpenNetworkSearch: {
                openNetworkSearch(with: messagePlainText(message))
            },
            onSaveMessageToKnowledge: {
                saveMessageToKnowledge(message)
            },
            onGenerateKnowledgeCardsPreview: {
                generateKnowledgeCardsPreview(for: message, metadata: metadata)
            },
            onSaveKnowledgeCard: { card in
                saveKnowledgeCard(card, from: message)
            },
            onTaskCardAction: handleTaskCardAction,
            onPendingMemberToolSelect: { card, memberID in
                Task {
                    await detailViewModel.setPendingMemberToolSelection(
                        threadID: threadID,
                        message: message,
                        card: card,
                        memberID: memberID
                    )
                }
            },
            onToolQuestionCardSubmit: { card, responses in
                Task {
                    await detailViewModel.submitInlineToolQuestionCard(
                        threadID: threadID,
                        message: message,
                        card: card,
                        responses: responses
                    )
                }
            },
            onToolMemberSelectionCardSubmit: { card, memberID in
                Task {
                    await detailViewModel.submitInlineToolMemberSelectionCard(
                        threadID: threadID,
                        message: message,
                        card: card,
                        memberID: memberID
                    )
                }
            },
            savingStructuredHealthCardIDs: detailViewModel.savingStructuredHealthCardIDs,
            savingNutritionCardIDs: detailViewModel.savingNutritionCardIDs,
            onStructuredHealthCardAction: handleStructuredHealthCardAction,
            onNutritionCardAction: handleNutritionCardAction,
            onCaptureOpenCamera: {
                stateStore.setCameraPresented(true, for: threadID)
            },
            onCaptureOpenPhotoLibrary: {
                stateStore.setPhotoPickerPresented(true, for: threadID)
            },
            onCaptureOpenFiles: onCaptureOpenFiles,
            onPresentToolPreview: { prompt, renderContext in
                detailViewModel.presentToolDetailPreview(prompt: prompt, renderContext: renderContext)
            },
            fileTransferService: detailViewModel.attachmentFileTransferService,
            medicalQueryAPI: detailViewModel.sparkMedicalQueryAPI,
            cachedMemberCompleteData: detailViewModel.cachedMemberCompleteData,
            onHealthResourceUnavailableTap: {
                detailViewModel.notifyHealthResourceUnavailable()
            },
            healthResourceDestinationFactory: { reference in
                AnyView(
                    HealthResourceReferenceDestination(
                        reference: reference,
                        medicalQueryAPI: detailViewModel.sparkMedicalQueryAPI,
                        fileTransferService: detailViewModel.attachmentFileTransferService,
                        memberContextStore: memberContextStore,
                        notificationClient: detailViewModel.chatNotificationClient,
                        cachedCompleteData: detailViewModel.cachedMemberCompleteData,
                        onCompleteDataPatched: { detailViewModel.updateCachedMemberCompleteData($0) },
                        logger: detailViewModel.chatLogger
                    )
                )
            },
            onHeightChangingUpdate: onHeightChangingUpdate
        )
    }

    private func handleStructuredHealthCardAction(_ action: ChatStructuredHealthCardAction) {
        Task {
            await detailViewModel.handleStructuredHealthCardAction(
                threadID: threadID,
                message: message,
                action: action
            )
        }
    }

    private func handleNutritionCardAction(_ action: ChatNutritionCardAction) {
        Task {
            await detailViewModel.handleNutritionCardAction(
                threadID: threadID,
                message: message,
                action: action
            )
        }
    }

    private func isLastAssistantMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        return visibleMessages.last(where: { $0.role == .assistant })?.id == message.id
    }

    private func toolMeta() -> (name: String, content: String)? {
        if let block = message.blocks.last(where: { $0.kind == .tool }),
           let rawContent = block.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           rawContent.isEmpty == false {
            return (
                ChatToolRuntimeAttachmentBuilder.localizedDisplayName(for: block.toolName),
                rawContent
            )
        }
        let name = ChatMessageMetadata(message: message).toolName ?? ""
        let rawContent = ChatMessageMetadata(message: message).toolContent ?? ""
        guard rawContent.isEmpty == false else { return nil }
        return (ChatToolRuntimeAttachmentBuilder.localizedDisplayName(for: name), rawContent)
    }

    private func operationalMeta() -> (state: String, description: String)? {
        guard message.deliveryState == .sending else { return nil }
        let metadata = ChatMessageMetadata(message: message)
        let storedState = metadata.operationalState ?? ""
        let storedDesc = metadata.operationalDescription ?? ""
        if storedState.isEmpty == false || storedDesc.isEmpty == false {
            return (storedState, storedDesc)
        }
        guard let tool = toolMeta() else { return nil }
        return ChatToolRuntimeAttachmentBuilder.makeOperationalMeta(
            toolName: ChatMessageMetadata(message: message).toolName,
            toolContent: tool.content
        )
    }

    private func knowledgeCards(from message: ChatMessage) -> [ChatKnowledgeCard] {
        let cards = message.blocks.flatMap(\.knowledgeCards)
        return cards.isEmpty ? ChatMessageMetadata(message: message).knowledgeCards : cards
    }

    private func combinedKnowledgeCards(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) -> [ChatKnowledgeCard] {
        let persisted = metadata?.knowledgeCards ?? knowledgeCards(from: message)
        let generated = uiStateStore.knowledgeCards(for: message.id)
        var dedup: Set<String> = []
        var merged: [ChatKnowledgeCard] = []
        for card in persisted + generated {
            let normalizedTitle = card.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedContent = card.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = "\(normalizedTitle)|\(normalizedContent)"
            guard dedup.insert(key).inserted else { continue }
            merged.append(card)
        }
        return merged
    }

    private func formatReasoningTime(_ durationMs: Int64?) -> String? {
        guard let durationMs, durationMs > 0 else { return nil }
        let seconds = Double(durationMs) / 1_000
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remainSeconds = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%dm %.1fs", minutes, remainSeconds)
    }

    private func openNetworkSearch(with text: String) {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else { return }
        let escaped = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        guard let url = URL(string: "https://www.bing.com/search?q=\(escaped)") else { return }
        UIApplication.shared.open(url)
    }

    private func saveMessageToKnowledge(_ message: ChatMessage) {
        guard uiStateStore.isMessageSaving(message.id) == false else { return }
        guard uiStateStore.isMessageSaved(message.id) == false else { return }
        Task {
            guard await actionState.beginSavingMessage(message.id) else { return }
            await MainActor.run {
                uiStateStore.setMessageSaving(true, for: message.id)
            }
            defer {
                Task {
                    await actionState.endSavingMessage(message.id)
                    await MainActor.run {
                        uiStateStore.setMessageSaving(false, for: message.id)
                    }
                }
            }
            do {
                try await messageActionUseCase.saveMessageToKnowledge(
                    content: messagePlainText(message),
                    detailViewModel: detailViewModel
                )
                await MainActor.run {
                    uiStateStore.setMessageSaved(true, for: message.id)
                }
            } catch {
                logger.error("保存消息到知识库失败：\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func toggleTranslate(_ message: ChatMessage) {
        if uiStateStore.translatedText(for: message.id)?.isEmpty == false {
            uiStateStore.setTranslatedText(nil, for: message.id)
            return
        }
        guard uiStateStore.isTranslating(message.id) == false else { return }
        Task {
            guard await actionState.beginTranslating(message.id) else { return }
            await MainActor.run {
                uiStateStore.setTranslating(true, for: message.id)
            }
            defer {
                Task {
                    await actionState.endTranslating(message.id)
                    await MainActor.run {
                        uiStateStore.setTranslating(false, for: message.id)
                    }
                }
            }
            do {
                let translated = try await messageActionUseCase.translate(messagePlainText(message), detailViewModel: detailViewModel)
                await MainActor.run {
                    uiStateStore.setTranslatedText(translated.trimmingCharacters(in: .whitespacesAndNewlines), for: message.id)
                }
            } catch {
                await MainActor.run {
                    uiStateStore.setTranslatedText(nil, for: message.id)
                }
            }
        }
    }

    private func handleTaskCardAction(_ action: TaskCard.Action) {
        switch action {
        case .confirm(let card):
            confirmTaskCard(card, action: action)
        case .ignore(let card), .setMember(let card, _):
            guard let message = messageContainingTaskCard(cardID: card.id) else { return }
            Task {
                await detailViewModel.handleTaskCardAction(threadID: threadID, message: message, action: action)
            }
        }
    }

    private func confirmTaskCard(_ card: TaskCard, action: TaskCard.Action) {
        guard uiStateStore.isTaskCardLoading(card.id) == false else { return }
        guard let message = messageContainingTaskCard(cardID: card.id) else { return }
        Task {
            guard await actionState.beginTaskCardLoading(card.id) else { return }
            await MainActor.run {
                uiStateStore.setTaskCardLoading(true, for: card.id)
            }
            defer {
                Task {
                    await actionState.endTaskCardLoading(card.id)
                    await MainActor.run {
                        uiStateStore.setTaskCardLoading(false, for: card.id)
                    }
                }
            }
            await detailViewModel.handleTaskCardAction(
                    threadID: threadID,
                    message: message,
                    action: action
            )
        }
    }

    private func messageContainingTaskCard(cardID: Int) -> ChatMessage? {
        visibleMessages.first { message in
            let cards = message.blocks.flatMap(\.taskCards)
            if cards.contains(where: { $0.id == cardID }) {
                return true
            }
            return ChatMessageMetadata(message: message).taskCards.contains(where: { $0.id == cardID })
        }
    }

    private func generateKnowledgeCardsPreview(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) {
        guard message.role == .assistant else { return }
        guard combinedKnowledgeCards(for: message).isEmpty else {
            logger.debug("知识卡预览已存在，跳过重新生成，message=\(message.id.uuidString)", module: .general)
            return
        }
        let resolved = metadata ?? ChatMessageMetadata(message: message)
        let card = messageActionUseCase.buildKnowledgePreviewCard(message: message, metadata: resolved)
        uiStateStore.setKnowledgeCards([card], for: message.id)
        logger.info("知识卡预览已生成，message=\(message.id.uuidString), title=\(card.title)", module: .general)
    }

    private func saveKnowledgeCard(_ card: ChatKnowledgeCard, from message: ChatMessage) {
        guard uiStateStore.isKnowledgeCardSaving(card.id) == false else { return }
        guard uiStateStore.isKnowledgeCardSaved(card.id) == false else { return }
        Task {
            guard await actionState.beginSavingKnowledgeCard(card.id) else { return }
            await MainActor.run {
                uiStateStore.setKnowledgeCardSaving(true, for: card.id)
            }
            defer {
                Task {
                    await actionState.endSavingKnowledgeCard(card.id)
                    await MainActor.run {
                        uiStateStore.setKnowledgeCardSaving(false, for: card.id)
                    }
                }
            }
            do {
                try await messageActionUseCase.saveKnowledgeCard(card, detailViewModel: detailViewModel)
                await MainActor.run {
                    uiStateStore.setKnowledgeCardSaved(true, for: card.id)
                }
                logger.info("知识卡保存成功，message=\(message.id.uuidString), card=\(card.id.uuidString)", module: .general)
            } catch {
                logger.error("知识卡保存失败：\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func translatedText(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) -> String? {
        if let local = uiStateStore.translatedText(for: message.id), local.isEmpty == false {
            return local
        }
        if let blockText = message.blocks.last(where: { $0.kind == .translatedText })?.text,
           blockText.isEmpty == false {
            return blockText
        }
        let attachment = metadata?.translatedText ?? ChatMessageMetadata(message: message).translatedText
        return attachment?.isEmpty == false ? attachment : nil
    }

    private func messagePlainText(_ message: ChatMessage) -> String {
        message.blocks
            .filter { $0.kind == .text || $0.kind == .tool || $0.kind == .error || $0.kind == .assistantStatusCard }
            .compactMap(\.text)
            .joined(separator: "\n")
    }

    private struct RowWidthPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}

struct ChatSelectableTextPayload: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}
