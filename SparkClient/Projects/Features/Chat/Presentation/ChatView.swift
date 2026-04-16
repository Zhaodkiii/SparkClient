import SwiftUI
import AVFoundation
import UIKit
import Combine

struct ChatView: View {
    let threadID: UUID
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var listViewModel: ChatListViewModel
    @ObservedObject var detailViewModel: ChatDetailViewModel

    @State private var hasLoaded = false
    @StateObject private var uiStateStore = ChatMessageUIStateStore()
    private let actionState = ChatMessageActionState()
    private let scrollThrottler = ChatScrollThrottler(minGenerationStep: 4)
    @State private var selectedTextSheet: SelectableTextPayload?
    @StateObject private var speechHelper = ChatSpeechHelper()
    @AppStorage(ChatComposerStyle.appStorageKey) private var composerStyleRaw = ChatComposerStyle.signal.rawValue
    @StateObject private var taskManager = TaskManager.shared
    private let logger: Logger = ConsoleLogger()
    private static let cardActionSnapshotStorageKeyPrefix = "chat.view.card_action_snapshot."
    private var messageActionUseCase: any ChatMessageActionUseCase {
        DefaultChatMessageActionUseCase(taskManager: taskManager, logger: logger)
    }

    private var reasoningRefreshId: String {
        let name = stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName ?? "-"
        return "\(threadID.uuidString)|\(name)"
    }

    private var composerStyle: ChatComposerStyle {
        ChatComposerStyle(rawValue: composerStyleRaw) ?? .signal
    }

    private var visibleMessages: [ChatMessage] {
        stateStore.selectedMessages.filter { uiStateStore.isDeleted($0.id) == false }
    }

    private var hasMoreMessages: Bool {
        stateStore.hasMoreMessages(for: threadID)
    }

    private var isLoadingMoreMessages: Bool {
        stateStore.isLoadingMoreMessages(for: threadID)
    }

    var body: some View {
        AnyView(configuredLayout)
    }

    private var baseLayout: some View {
        VStack(spacing: 0) {
            messageList

            Group {
                switch composerStyle {
                case .signal:
                    ChatComposerView(
                        threadID: threadID,
                        stateStore: stateStore,
                        onSend: {
                            KeyboardDismissHelper.dismissKeyboard()
                            Task { await detailViewModel.sendCurrentDraft() }
                        }
                    )
                case .hanlin:
                    HanlinChatComposerView(
                        threadID: threadID,
                        modelReasoning: detailViewModel.reasoningToolbarContext,
                        stateStore: stateStore,
                        modelRows: detailViewModel.chatScenarioModels,
                        onSend: {
                            KeyboardDismissHelper.dismissKeyboard()
                            Task { await detailViewModel.sendCurrentDraft() }
                        }
                    )
                }
            }
        }
    }

    private var configuredLayout: some View {
        lifecycleLayout
    }

    private var navigationDecoratedLayout: some View {
        baseLayout
            .navigationTitle(stateStore.selectedThread?.listDisplayTitle ?? L10n.text("chat.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker(L10n.text("chat.composer.style.title"), selection: $composerStyleRaw) {
                            Text(L10n.text("chat.composer.style.signal")).tag(ChatComposerStyle.signal.rawValue)
                            Text(L10n.text("chat.composer.style.hanlin")).tag(ChatComposerStyle.hanlin.rawValue)
                        }
                    } label: {
                        Label(L10n.text("chat.composer.style.title"), systemImage: "rectangle.split.2x1")
                    }
                }
            }
    }

    private var initialLoadLayout: some View {
        navigationDecoratedLayout
            .task {
                guard hasLoaded == false else { return }
                hasLoaded = true
                listViewModel.selectThread(threadID)
                await detailViewModel.loadMessagesIfNeeded(for: threadID)
                restoreCardActionSnapshotIfNeeded(forceReload: true)
            }
            .onChange(of: threadID) { _ in
                restoreCardActionSnapshotIfNeeded(forceReload: true)
            }
    }

    private var statePersistenceLayoutStep1: some View {
        initialLoadLayout
            .onChange(of: uiStateStore.savedKnowledgeCardIDs) { _ in
                persistCardActionSnapshot()
            }
            .onChange(of: uiStateStore.savedMessageIDs) { _ in
                persistCardActionSnapshot()
            }
    }

    private var statePersistenceLayout: some View {
        statePersistenceLayoutStep1
            .onChange(of: uiStateStore.ignoredTaskCardIDs) { _ in
                persistCardActionSnapshot()
            }
            .onChange(of: uiStateStore.createdTaskCardIDs) { _ in
                persistCardActionSnapshot()
            }
    }

    private var lifecycleLayout: some View {
        statePersistenceLayout
            .task(id: threadID) {
                await detailViewModel.refreshChatModelPicker()
            }
            .task(id: reasoningRefreshId) {
                await detailViewModel.refreshReasoningToolbarContext(for: threadID)
            }
            .sheet(item: $selectedTextSheet) { payload in
                NavigationView {
                    ScrollView {
                        Text(payload.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(payload.title)
                }
                .navigationViewStyle(.stack)
            }
            .onAppear {
                Task { await detailViewModel.chatPageDidAppear() }
            }
            .onDisappear {
                Task { await detailViewModel.chatPageDidDisappear() }
            }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if hasMoreMessages {
                        HStack {
                            Spacer()
                            if isLoadingMoreMessages {
                                ProgressView()
                            } else {
                                Text(L10n.text("chat.history.load_more"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .onAppear {
                            Task {
                                await detailViewModel.loadMoreMessages(for: threadID)
                            }
                        }
                    }

                    ForEach(visibleMessages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if stateStore.isSending {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
                .padding(.vertical, 16)
            }
            .chatScrollDismissesKeyboardInteractively()
            .onAppear {
                scrollToLastMessage(proxy: proxy, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    scrollToLastMessage(proxy: proxy, animated: false)
                }
            }
            .onChange(of: visibleMessages.last?.id) { _ in
                scrollToLastMessage(proxy: proxy, animated: true)
            }
            .onChange(of: stateStore.streamingContentGeneration) { generation in
                Task {
                    if await scrollThrottler.shouldScroll(generation: generation) {
                        await MainActor.run {
                            scrollToLastMessage(proxy: proxy, animated: false)
                        }
                    }
                }
            }
            .refreshable {
                await detailViewModel.sync()
                await detailViewModel.loadMessagesIfNeeded(for: threadID)
                await listViewModel.refreshThreads()
            }
        }
    }

    private func scrollToLastMessage(proxy: ScrollViewProxy, animated: Bool) {
        if let lastID = visibleMessages.last?.id {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    /// 对齐 AI_HLY 的 `isLastAssistantGroup` 语义：
    /// 仅最后一条助手消息在“流式思考中”时展示三行动态推理预览。
    private func isLastAssistantMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        return visibleMessages.last(where: { $0.role == .assistant })?.id == message.id
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .assistant || message.role == .system {
                bubbleContent(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 40)
                bubbleContent(message)
            }
        }
        .padding(.trailing, 16)
    }

    /// 渲染单条聊天消息的气泡内容（根据消息角色和类型展示不同组件）
    /// - Parameter message: 聊天消息模型
    /// - Returns: 消息气泡视图
    private func bubbleContent(_ message: ChatMessage) -> AnyView {
        let metadata = ChatMessageMetadata(message: message)
        return AnyView(
            ChatMessageBubbleContentView(
                message: message,
                metadata: metadata,
                isLastAssistantMessage: isLastAssistantMessage(message),
                translatedText: translatedText(for: message, metadata: metadata),
                combinedKnowledgeCards: combinedKnowledgeCards(for: message, metadata: metadata),
                isMathMode: uiStateStore.isMathMode(message.id),
                isTranslating: uiStateStore.isTranslating(message.id),
                isSavingMessage: uiStateStore.isMessageSaving(message.id),
                isSavedMessage: uiStateStore.isMessageSaved(message.id),
                isSpeaking: speechHelper.isSpeaking(message.id),
                taskCardLoadingIDs: uiStateStore.taskCardLoadingIDs,
                ignoredTaskCardIDs: uiStateStore.ignoredTaskCardIDs,
                createdTaskCardIDs: uiStateStore.createdTaskCardIDs,
                savingKnowledgeCardIDs: uiStateStore.savingKnowledgeCardIDs,
                savedKnowledgeCardIDs: uiStateStore.savedKnowledgeCardIDs,
                savingMedicalCardIDs: uiStateStore.savingMedicalCardIDs,
                showActions: message.id == visibleMessages.last?.id,
                onRetry: {
                    Task {
                        await detailViewModel.retryFailedMessage(clientMessageID: message.clientMessageID)
                    }
                },
                onCopy: {
                    UIPasteboard.general.string = message.content
                },
                onDelete: {
                    uiStateStore.markDeleted(message.id)
                },
                onToggleSpeech: {
                    speechHelper.toggle(text: message.content, id: message.id)
                },
                onToggleTranslate: {
                    toggleTranslate(message)
                },
                onOpenNetworkSearch: {
                    openNetworkSearch(with: message.content)
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
                onConfirmTaskCard: { card in
                    confirmTaskCard(card)
                },
                onIgnoreTaskCard: { card in
                    ignoreTaskCard(card)
                },
                onSaveMedicationCard: { card in
                    saveMedicationCard(card, from: message)
                },
                onSavePrescriptionCard: { card in
                    savePrescriptionCard(card, from: message)
                },
                onSaveExamReportCard: { card in
                    saveExamReportCard(card, from: message)
                },
                onSaveMedicalCaseCard: { card in
                    saveMedicalCaseCard(card, from: message)
                }
            )
        )
    }

    private func toolMeta(from message: ChatMessage, metadata: ChatMessageMetadata) -> (name: String, content: String)? {
        let name = metadata.toolName ?? ""
        let rawContent = metadata.toolContent ?? ""
        guard rawContent.isEmpty == false else { return nil }
        return (name.isEmpty ? L10n.text("chat.bubble.tool.default_name") : name, rawContent)
    }

    private func shouldShowToolContentBlock(metadata: ChatMessageMetadata) -> Bool {
        true
    }

    /// 对齐 AI_HLY 的 operationalState / operationalDescription：
    /// - operationalState：当前工具执行状态（例如“正在使用工具：xxx”）
    /// - operationalDescription：工具过程描述（多行，UI 仅展示最近三行）
    private func operationalMeta(from message: ChatMessage, metadata: ChatMessageMetadata) -> (state: String, description: String)? {
        guard message.deliveryState == .sending else { return nil }
        let storedState = metadata.operationalState ?? ""
        let storedDesc = metadata.operationalDescription ?? ""
        if storedState.isEmpty == false || storedDesc.isEmpty == false {
            return (storedState, storedDesc)
        }
        guard let tool = toolMeta(from: message, metadata: metadata) else { return nil }
        let lines = tool.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let state: String
        if let first = lines.first, first.hasPrefix("使用工具：") {
            state = first
        } else {
            state = L10n.text("chat.bubble.tool.operating_prefix") + tool.name
        }
        let description = lines.dropFirst().joined(separator: "\n")
        return (state, description)
    }

    private func knowledgeCards(from message: ChatMessage) -> [ChatKnowledgeCard] {
        ChatMessageMetadata(message: message).knowledgeCards
    }

    private func combinedKnowledgeCards(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) -> [ChatKnowledgeCard] {
        // 合并“持久化卡片 + 本地临时卡片”，并按 title+content 做去重。
        // 这样可以兼容：服务器返回卡片 + 用户手动点击“生成知识卡预览”。
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

    private func shouldRenderMainMarkdown(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) -> Bool {
        guard message.role == .assistant else { return true }
        guard message.kind == .tool else { return true }
        let resolvedMeta = metadata ?? ChatMessageMetadata(message: message)
        let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.isEmpty == false else { return false }
        let toolContent = resolvedMeta.toolContent ?? ""
        if toolContent.isEmpty {
            return true
        }
        return trimmedContent != toolContent
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
                    content: message.content,
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
                let translated = try await messageActionUseCase.translate(message.content, detailViewModel: detailViewModel)
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

    /// 点击“创建任务”：直接创建 Task 总表与子任务，不再走 TaskCard 服务端接口。
    private func confirmTaskCard(_ card: TaskCard) {
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
            do {
                try await messageActionUseCase.createTask(from: card)
                await detailViewModel.updateTaskCardStatus(
                    threadID: threadID,
                    message: message,
                    cardID: card.id,
                    status: .confirmed
                )
            } catch {
                logger.error("任务卡片直接创建任务失败 card_id=\(card.id) error=\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func ignoreTaskCard(_ card: TaskCard) {
        guard let message = messageContainingTaskCard(cardID: card.id) else { return }
        Task {
            await detailViewModel.updateTaskCardStatus(
                threadID: threadID,
                message: message,
                cardID: card.id,
                status: .ignored
            )
        }
        logger.info("任务卡片本地忽略 card_id=\(card.id)", module: .general)
    }

    private func messageContainingTaskCard(cardID: Int) -> ChatMessage? {
        visibleMessages.first { message in
            ChatMessageMetadata(message: message).taskCards.contains(where: { $0.id == cardID })
        }
    }

    private func generateKnowledgeCardsPreview(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) {
        guard message.role == .assistant else { return }
        guard combinedKnowledgeCards(for: message).isEmpty else {
            // 该消息已经存在可展示卡片，不重复生成，避免 UI 重复。
            logger.debug("知识卡预览已存在，跳过重新生成，message=\(message.id.uuidString)", module: .general)
            return
        }
        // 仅生成预览，不直接落库。
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

    private func saveMedicationCard(_ card: ChatMedicationCardPayload, from message: ChatMessage) {
        guard card.isSaved == false else { return }
        guard uiStateStore.isMedicalCardSaving(card.id) == false else { return }
        Task {
            await MainActor.run { uiStateStore.setMedicalCardSaving(true, for: card.id) }
            defer { Task { await MainActor.run { uiStateStore.setMedicalCardSaving(false, for: card.id) } } }
            do {
                try await messageActionUseCase.saveMedicationCard(card, message: message, threadID: threadID, detailViewModel: detailViewModel)
            } catch {
                logger.error("用药卡保存失败：\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func savePrescriptionCard(_ card: ChatPrescriptionCardPayload, from message: ChatMessage) {
        guard card.isSaved == false else { return }
        guard uiStateStore.isMedicalCardSaving(card.id) == false else { return }
        Task {
            await MainActor.run { uiStateStore.setMedicalCardSaving(true, for: card.id) }
            defer { Task { await MainActor.run { uiStateStore.setMedicalCardSaving(false, for: card.id) } } }
            do {
                try await messageActionUseCase.savePrescriptionCard(card, message: message, threadID: threadID, detailViewModel: detailViewModel)
            } catch {
                logger.error("处方卡保存失败：\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func saveExamReportCard(_ card: ChatExamReportCardPayload, from message: ChatMessage) {
        guard card.isSaved == false else { return }
        guard uiStateStore.isMedicalCardSaving(card.id) == false else { return }
        Task {
            await MainActor.run { uiStateStore.setMedicalCardSaving(true, for: card.id) }
            defer { Task { await MainActor.run { uiStateStore.setMedicalCardSaving(false, for: card.id) } } }
            do {
                try await messageActionUseCase.saveExamReportCard(card, message: message, threadID: threadID, detailViewModel: detailViewModel)
            } catch {
                logger.error("检查报告卡保存失败：\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func saveMedicalCaseCard(_ card: ChatMedicalCaseCardPayload, from message: ChatMessage) {
        guard card.isSaved == false else { return }
        guard uiStateStore.isMedicalCardSaving(card.id) == false else { return }
        Task {
            await MainActor.run { uiStateStore.setMedicalCardSaving(true, for: card.id) }
            defer { Task { await MainActor.run { uiStateStore.setMedicalCardSaving(false, for: card.id) } } }
            do {
                try await messageActionUseCase.saveMedicalCaseCard(card, message: message, threadID: threadID, detailViewModel: detailViewModel)
            } catch {
                logger.error("病例卡保存失败：\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func translatedText(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) -> String? {
        if let local = uiStateStore.translatedText(for: message.id), local.isEmpty == false {
            return local
        }
        let attachment = metadata?.translatedText ?? ChatMessageMetadata(message: message).translatedText
        return attachment?.isEmpty == false ? attachment : nil
    }

    private var cardActionSnapshotStorageKey: String {
        Self.cardActionSnapshotStorageKeyPrefix + threadID.uuidString.lowercased()
    }

    private func restoreCardActionSnapshotIfNeeded(forceReload: Bool = false) {
        if forceReload {
            uiStateStore.applyCardActionSnapshot(.empty, forceReload: true)
        }
        guard let data = UserDefaults.standard.data(forKey: cardActionSnapshotStorageKey) else { return }
        guard let snapshot = try? JSONDecoder().decode(CardActionSnapshot.self, from: data) else { return }
        uiStateStore.applyCardActionSnapshot(snapshot, forceReload: false)
    }

    private func persistCardActionSnapshot() {
        let snapshot = uiStateStore.makeCardActionSnapshot()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: cardActionSnapshotStorageKey)
    }

    private func htmlContent(from message: ChatMessage) -> String? {
        ChatMessageMetadata(message: message).htmlContent
    }

    private func imagePayloads(from message: ChatMessage) -> [ChatImagePayload] {
        var payloads: [ChatImagePayload] = []
        for attachment in message.attachments where attachment.type == "image_url" || attachment.type == "image_base64" {
            let raw = attachment.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard raw.isEmpty == false else { continue }
            if let image = decodeImage(from: raw) {
                payloads.append(ChatImagePayload(id: attachment.id, url: nil, image: image))
            } else if let url = URL(string: raw) {
                payloads.append(ChatImagePayload(id: attachment.id, url: url, image: nil))
            }
        }
        return payloads
    }

    private func decodeImage(from text: String) -> UIImage? {
        if text.hasPrefix("data:image"),
           let base64 = text.components(separatedBy: ",").last,
           let data = Data(base64Encoded: base64) {
            return UIImage(data: data)
        }
        if let data = Data(base64Encoded: text) {
            return UIImage(data: data)
        }
        return nil
    }

    private func mapLocations(from message: ChatMessage) -> [ChatMapLocationPayload] {
        ChatMessageMetadata(message: message).locations
    }

    private func mapRoutes(from message: ChatMessage) -> [ChatRoutePayload] {
        ChatMessageMetadata(message: message).routes
    }

    private func eventPayloads(from message: ChatMessage) -> [ChatEventPayload] {
        ChatMessageMetadata(message: message).events
    }

    private func healthCardPayloads(from message: ChatMessage) -> [ChatHealthCardPayload] {
        ChatMessageMetadata(message: message).healthCards
    }
}

private struct SelectableTextPayload: Identifiable {
    let id: UUID = UUID()
    let title: String
    let text: String
}

private final class ChatSpeechHelper: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    @Published private var speakingMessageID: UUID?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(text: String, id: UUID) {
        if speakingMessageID == id {
            synthesizer.stopSpeaking(at: .immediate)
            speakingMessageID = nil
            return
        }
        speakingMessageID = id
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func isSpeaking(_ id: UUID) -> Bool {
        speakingMessageID == id && synthesizer.isSpeaking
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speakingMessageID = nil
    }
}
