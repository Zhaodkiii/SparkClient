import Combine
import Foundation

struct ChatComposerModelOption: Identifiable, Equatable, Sendable {
    let id: String
    let modelName: String
    let title: String
    let iconSystemName: String

    init(modelName: String, title: String, iconSystemName: String = "cpu") {
        self.id = modelName
        self.modelName = modelName
        self.title = title
        self.iconSystemName = iconSystemName
    }
}

@MainActor
final class ChatDetailViewModel: ObservableObject {
    private enum MessagePagingConfig {
        static let initialLimit = 6
        static let loadMoreLimit = 10
    }

    private let stateStore: ChatStateStore
    private let memberContextStore: MemberContextStore
    private let loadChatThreadsUseCase: LoadChatThreadsUseCase
    private let loadChatMessagesUseCase: LoadChatMessagesUseCase
    private let sendMessageUseCase: SendChatMessageUseCase
    private let retryFailedMessageUseCase: RetryFailedMessageUseCase
    private let syncChatUseCase: SyncChatUseCase
    private let notificationClient: any NotificationClient
    private let aiConfigCenter: AIConfigCenter
    private let aiSettingsRepository: any AISettingsRepository
    private let translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase
    private let createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase
    private let logger: Logger
    private var isRealtimeActive = false

    /// 对话场景可选模型行（远程场景 + 本地/智能体模型），供 Hanlin 输入栏展示。
    @Published private(set) var chatScenarioModels: [ChatComposerModelOption] = []
    /// 当前会话输入栏关联模型的推理能力（用于思考开关展示策略）。
    @Published private(set) var reasoningToolbarContext: ChatModelReasoningContext = .unknown

    init(
        stateStore: ChatStateStore,
        memberContextStore: MemberContextStore,
        loadChatThreadsUseCase: LoadChatThreadsUseCase,
        loadChatMessagesUseCase: LoadChatMessagesUseCase,
        sendMessageUseCase: SendChatMessageUseCase,
        retryFailedMessageUseCase: RetryFailedMessageUseCase,
        syncChatUseCase: SyncChatUseCase,
        notificationClient: any NotificationClient,
        aiConfigCenter: AIConfigCenter,
        aiSettingsRepository: any AISettingsRepository,
        translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase,
        createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase,
        logger: Logger = ConsoleLogger()
    ) {
        self.stateStore = stateStore
        self.memberContextStore = memberContextStore
        self.loadChatThreadsUseCase = loadChatThreadsUseCase
        self.loadChatMessagesUseCase = loadChatMessagesUseCase
        self.sendMessageUseCase = sendMessageUseCase
        self.retryFailedMessageUseCase = retryFailedMessageUseCase
        self.syncChatUseCase = syncChatUseCase
        self.notificationClient = notificationClient
        self.aiConfigCenter = aiConfigCenter
        self.aiSettingsRepository = aiSettingsRepository
        self.translateKnowledgeTextUseCase = translateKnowledgeTextUseCase
        self.createKnowledgeDocumentUseCase = createKnowledgeDocumentUseCase
        self.logger = logger
    }

    func refreshChatModelPicker() async {
        let snapshot = await aiSettingsRepository.loadSnapshot()
        let models = snapshot.allModels
            .filter { model in
                model.isHidden == false &&
                model.supportsText &&
                snapshot.shouldOfferTrialModelInChatPicker(modelName: model.name) &&
                canUseInChatPicker(model: model, snapshot: snapshot)
            }
            .sorted { $0.position < $1.position }

        let options = models.map { model in
            ChatComposerModelOption(
                modelName: model.name,
                title: model.displayName,
                iconSystemName: model.identity == .agent
                    ? (model.iconSymbol?.isEmpty == false ? model.iconSymbol! : "person.crop.circle")
                    : "cpu"
            )
        }
        chatScenarioModels = options
    }

    func refreshReasoningToolbarContext(for threadID: UUID) async {
        let snapshot = await aiSettingsRepository.loadSnapshot()
        let name = await MainActor.run {
            stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName
        }
        let ctx = snapshot.chatReasoningContext(selectedModelName: name)
        await MainActor.run {
            reasoningToolbarContext = ctx
        }
    }

    private func applyChatModelRuntimeOverride(selectedName: String?) async {
        let snapshot = await aiSettingsRepository.loadSnapshot()
        guard let name = selectedName, name.isEmpty == false else {
            await aiConfigCenter.clearRuntimeOverride(for: .chat)
            return
        }

        if let selected = snapshot.allModels.first(where: { $0.name == name }) {
            if selected.company.uppercased() == LocalModelService.localCompany {
                await aiConfigCenter.setRuntimeOverride(
                    AIScenarioConfig(
                        endpoint: "local://chat/completions",
                        model: selected.name,
                        apiKey: nil,
                        temperature: snapshot.chat.temperature,
                        maxTokens: snapshot.chat.maxTokens
                    ),
                    for: .chat
                )
                return
            }

            if selected.identity == .agent,
               let baseModelName = selected.baseModelName,
               let base = snapshot.allModels.first(where: { $0.name == baseModelName }) {
                let endpoint = endpointForModelCompany(base.company, snapshot: snapshot) ?? snapshot.chat.endpoint
                let apiKey = apiKeyForModelCompany(base.company, snapshot: snapshot)
                await aiConfigCenter.setRuntimeOverride(
                    AIScenarioConfig(
                        endpoint: endpoint,
                        model: base.name,
                        apiKey: apiKey,
                        temperature: snapshot.chat.temperature,
                        maxTokens: snapshot.chat.maxTokens
                    ),
                    for: .chat
                )
                return
            }

            let endpoint = endpointForModelCompany(selected.company, snapshot: snapshot) ?? snapshot.chat.endpoint
            let apiKey = apiKeyForModelCompany(selected.company, snapshot: snapshot)
            await aiConfigCenter.setRuntimeOverride(
                AIScenarioConfig(
                    endpoint: endpoint,
                    model: selected.name,
                    apiKey: apiKey,
                    temperature: snapshot.chat.temperature,
                    maxTokens: snapshot.chat.maxTokens
                ),
                for: .chat
            )
            return
        }

        if let bundle = snapshot.scenarioRemoteBundles?.chat,
           let row = bundle.models.first(where: { $0.model == name }) {
            await aiConfigCenter.setRuntimeOverride(row.asScenarioConfig(), for: .chat)
            return
        }

        await aiConfigCenter.clearRuntimeOverride(for: .chat)
    }

    private func endpointForModelCompany(_ company: String, snapshot: AISettingsSnapshot) -> String? {
        snapshot.apiKeys.first(where: {
            $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            == company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        })?.requestURL
    }

    private func apiKeyForModelCompany(_ company: String, snapshot: AISettingsSnapshot) -> String? {
        let raw = snapshot.apiKeys.first(where: {
            $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            == company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        })?.key ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func canUseInChatPicker(model: AllModels, snapshot: AISettingsSnapshot) -> Bool {
        let localCompany = LocalModelService.localCompany.uppercased()
        let company = model.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if company == localCompany {
            return true
        }

        let provider = snapshot.apiKeys.first(where: {
            $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == company
        })
        guard let provider else { return false }
        return provider.isHidden == false &&
        provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func loadMessagesIfNeeded(for threadID: UUID) async {
        let total = await loadChatMessagesUseCase.count(threadID: threadID)
        let messages = await loadChatMessagesUseCase.execute(
            threadID: threadID,
            limit: MessagePagingConfig.initialLimit,
            before: nil
        )
        let hasMore = total > messages.count
        stateStore.setMessages(messages, for: threadID, hasMore: hasMore)

        // 本地优先展示，再异步做远端增量同步，避免进入会话瞬时 UI 抖动。
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.syncChatUseCase.syncThreadOnOpen(threadID: threadID)
                let latestTotal = await self.loadChatMessagesUseCase.count(threadID: threadID)
                let latestMessages = await self.loadChatMessagesUseCase.execute(
                    threadID: threadID,
                    limit: MessagePagingConfig.initialLimit,
                    before: nil
                )
                let latestHasMore = latestTotal > latestMessages.count
                await MainActor.run {
                    self.stateStore.setMessages(latestMessages, for: threadID, hasMore: latestHasMore)
                }
            } catch {
                await MainActor.run {
                    self.stateStore.setError(error.localizedDescription)
                }
                self.logger.warning("会话打开同步失败：\(error.localizedDescription)", module: .general)
            }
        }
    }

    func loadMoreMessages(for threadID: UUID) async {
        guard stateStore.hasMoreMessages(for: threadID) else { return }
        guard stateStore.isLoadingMoreMessages(for: threadID) == false else { return }
        guard let oldest = stateStore.selectedMessages.first?.createdAt else { return }

        stateStore.setLoadingMore(true, for: threadID)
        defer { stateStore.setLoadingMore(false, for: threadID) }

        let older = await loadChatMessagesUseCase.execute(
            threadID: threadID,
            limit: MessagePagingConfig.loadMoreLimit,
            before: oldest
        )
        let hasMore = older.count >= MessagePagingConfig.loadMoreLimit
        stateStore.prependMessages(older, for: threadID, hasMore: hasMore)
    }

    func sendCurrentDraft() async {
        guard stateStore.isSending == false else { return }
        guard let threadID = stateStore.selectedThreadID else { return }

        let draft = stateStore.draft(for: threadID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.isEmpty == false else { return }

        let flags = stateStore.composerDraft(for: threadID).runtimeFlags
        let inference = ChatOrchestratorInferenceOptions(
            useTools: flags.useTools,
            useKnowledgeBag: flags.useKnowledgeBag,
            useWebSearch: flags.useWebSearch,
            reasoningEnabled: flags.reasoningEnabled,
            reasoningEffortTier: flags.reasoningEffortTier
        )

        logger.info(
            "发送对话开始，thread=\(shortID(threadID)), member=\(shortID(memberContextStore.context.selectedMemberID)), length=\(draft.count)",
            module: .general
        )
        stateStore.setSending(true)
        defer { stateStore.setSending(false) }

        do {
            await applyChatModelRuntimeOverride(selectedName: flags.selectedChatModelName)
            let modelReasoning = await aiSettingsRepository.loadSnapshot()
                .chatReasoningContext(selectedModelName: flags.selectedChatModelName)
            let streamingMessageID = UUID()
            let stateStore = self.stateStore
            stateStore.startStreamingAssistant(
                threadID: threadID,
                clientMessageID: streamingMessageID,
                kind: .text
            )
            let loadChatThreadsUseCase = self.loadChatThreadsUseCase
            let snapshot = try await sendMessageUseCase.execute(
                threadID: threadID,
                memberID: memberContextStore.context.selectedMemberID,
                userInput: draft,
                inference: inference,
                modelReasoning: modelReasoning,
                onUserMessagePersisted: { localSnapshot in
                    let threadItems = await loadChatThreadsUseCase.execute()
                    await MainActor.run {
                        stateStore.setSelectedThreadID(localSnapshot.thread.id)
                        // 保留流式占位：setMessages 默认会清空 streamingAssistants，会导致后续 onAssistantPartial 全部失效。
                        stateStore.setMessages(localSnapshot.messages, for: localSnapshot.thread.id, clearStreamingAssistant: false)
                        stateStore.setThreads(threadItems)
                        stateStore.clearDraft(for: localSnapshot.thread.id)
                    }
                },
                onAssistantPartial: { delta in
                    await MainActor.run {
                        stateStore.updateStreamingAssistant(threadID: threadID, delta: delta)
                    }
                }
            )
            let finalItems = await loadChatThreadsUseCase.execute()
            stateStore.setThreads(finalItems)
            stateStore.setMessages(snapshot.messages, for: snapshot.thread.id)
            stateStore.clearDraft(for: snapshot.thread.id)
            stateStore.setError(nil)
            logger.info(
                "发送对话完成，thread=\(shortID(snapshot.thread.id)), messages=\(snapshot.messages.count)",
                module: .general
            )
        } catch {
            stateStore.finishStreamingAssistant(threadID: threadID)
            stateStore.setError(error.localizedDescription)
            logger.error("发送对话失败：\(error.localizedDescription)", module: .general)
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.send")
        }
    }

    func retryFailedMessage(clientMessageID: UUID) async {
        logger.info("重试失败消息开始，clientMessageID=\(shortID(clientMessageID))", module: .general)
        do {
            try await retryFailedMessageUseCase.execute(clientMessageID: clientMessageID)
            if let threadID = stateStore.selectedThreadID {
                let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
                stateStore.setMessages(messages, for: threadID)
            }
            logger.info("重试失败消息完成，clientMessageID=\(shortID(clientMessageID))", module: .general)
        } catch {
            stateStore.setError(error.localizedDescription)
            logger.error("重试失败消息失败：\(error.localizedDescription)", module: .general)
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "chat.retry")
        }
    }

    func sync() async {
        logger.debug("手动聊天同步开始", module: .general)
        do {
            try await syncChatUseCase.execute()
            if let threadID = stateStore.selectedThreadID {
                let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
                stateStore.setMessages(messages, for: threadID)
            }
            logger.debug("手动聊天同步完成", module: .general)
        } catch {
            stateStore.setError(error.localizedDescription)
            logger.error("手动聊天同步失败：\(error.localizedDescription)", module: .general)
        }
    }

    func chatPageDidAppear() async {
        guard isRealtimeActive == false else { return }
        isRealtimeActive = true
        await syncChatUseCase.startRealtime()
    }

    func chatPageDidDisappear() async {
        guard isRealtimeActive else { return }
        isRealtimeActive = false
        await syncChatUseCase.stopRealtime()
    }

    func translateMessageText(_ text: String) async throws -> String {
        try await translateKnowledgeTextUseCase.execute(text: text)
    }

    func saveMessageAsKnowledge(content: String, suggestedTitle: String?) async throws -> KnowledgeDocument {
        let fallback = String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        let title = (suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? suggestedTitle!.trimmingCharacters(in: .whitespacesAndNewlines)
            : (fallback.isEmpty ? "聊天知识" : fallback)
        logger.info("保存消息为知识开始，title=\(title)", module: .general)
        // 兼容旧入口：直接将整条消息保存为知识文档。
        return try await createKnowledgeDocumentUseCase.execute(
            KnowledgeDocumentDraft(
                title: title,
                content: content,
                source: .tool
            )
        )
    }

    /// 保存消息内“已生成的知识卡”，用于卡片预览后的显式确认保存。
    func saveKnowledgeCard(title: String, content: String) async throws -> KnowledgeDocument {
        // 标题兜底策略：
        // 1) 优先使用卡片标题；
        // 2) 标题为空时，用正文前缀；
        // 3) 仍为空时，使用默认标题。
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        let resolvedTitle = trimmedTitle.isEmpty ? (fallback.isEmpty ? "聊天知识" : fallback) : trimmedTitle
        logger.info("保存知识卡开始，title=\(resolvedTitle)", module: .general)
        do {
            let document = try await createKnowledgeDocumentUseCase.execute(
                KnowledgeDocumentDraft(
                    title: resolvedTitle,
                    content: content,
                    source: .tool
                )
            )
            logger.info("保存知识卡完成，title=\(resolvedTitle)", module: .general)
            // 成功后统一给轻提示，确保用户知道“已入库”。
            notificationClient.success(
                L10n.text("chat.bubble.knowledge.saved.toast"),
                title: nil,
                source: "chat.knowledge.save"
            )
            return document
        } catch {
            // 失败路径保留错误提示与日志，便于后续定位落库问题。
            logger.error("保存知识卡失败：\(error.localizedDescription)", module: .general)
            notificationClient.error(
                error.localizedDescription,
                title: L10n.text("common.error"),
                source: "chat.knowledge.save"
            )
            throw error
        }
    }

    private func shortID(_ value: UUID?) -> String {
        guard let value else { return "-" }
        return String(value.uuidString.prefix(8))
    }

    private func shortID(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(value)
    }
}
