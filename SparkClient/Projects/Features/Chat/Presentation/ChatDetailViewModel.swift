import Combine
import Foundation

@MainActor
final class ChatDetailViewModel: ObservableObject {
    private let stateStore: ChatStateStore
    private let patientContextStore: PatientContextStore
    private let loadChatThreadsUseCase: LoadChatThreadsUseCase
    private let loadChatMessagesUseCase: LoadChatMessagesUseCase
    private let sendMessageUseCase: SendChatMessageUseCase
    private let retryFailedMessageUseCase: RetryFailedMessageUseCase
    private let syncChatUseCase: SyncChatUseCase
    private let notificationClient: any NotificationClient
    private let aiConfigCenter: AIConfigCenter
    private let aiSettingsRepository: any AISettingsRepository
    private let logger: Logger
    private var isRealtimeActive = false

    /// 对话场景可选模型行（来自远程 bundle），供 Hanlin 输入栏展示。
    @Published private(set) var chatScenarioModels: [AIScenarioRemoteModelRow] = []
    /// 当前会话输入栏关联模型的推理能力（用于思考开关展示策略）。
    @Published private(set) var reasoningToolbarContext: ChatModelReasoningContext = .unknown

    init(
        stateStore: ChatStateStore,
        patientContextStore: PatientContextStore,
        loadChatThreadsUseCase: LoadChatThreadsUseCase,
        loadChatMessagesUseCase: LoadChatMessagesUseCase,
        sendMessageUseCase: SendChatMessageUseCase,
        retryFailedMessageUseCase: RetryFailedMessageUseCase,
        syncChatUseCase: SyncChatUseCase,
        notificationClient: any NotificationClient,
        aiConfigCenter: AIConfigCenter,
        aiSettingsRepository: any AISettingsRepository,
        logger: Logger = ConsoleLogger()
    ) {
        self.stateStore = stateStore
        self.patientContextStore = patientContextStore
        self.loadChatThreadsUseCase = loadChatThreadsUseCase
        self.loadChatMessagesUseCase = loadChatMessagesUseCase
        self.sendMessageUseCase = sendMessageUseCase
        self.retryFailedMessageUseCase = retryFailedMessageUseCase
        self.syncChatUseCase = syncChatUseCase
        self.notificationClient = notificationClient
        self.aiConfigCenter = aiConfigCenter
        self.aiSettingsRepository = aiSettingsRepository
        self.logger = logger
    }

    func refreshChatModelPicker() async {
        let snapshot = await aiSettingsRepository.loadSnapshot()
        let rows = snapshot.scenarioRemoteBundles?.chat.models ?? []
        chatScenarioModels = rows.filter { snapshot.shouldOfferTrialModelInChatPicker(modelName: $0.model) }
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
        guard let bundle = snapshot.scenarioRemoteBundles?.chat else {
            await aiConfigCenter.clearRuntimeOverride(for: .chat)
            return
        }
        guard let name = selectedName, name.isEmpty == false,
              let row = bundle.models.first(where: { $0.model == name })
        else {
            await aiConfigCenter.clearRuntimeOverride(for: .chat)
            return
        }
        await aiConfigCenter.setRuntimeOverride(row.asScenarioConfig(), for: .chat)
    }

    func loadMessagesIfNeeded(for threadID: UUID) async {
        do {
            try await syncChatUseCase.syncThreadOnOpen(threadID: threadID)
        } catch {
            stateStore.setError(error.localizedDescription)
            logger.warning("会话打开同步失败：\(error.localizedDescription)", module: .general)
        }
        let messages = await loadChatMessagesUseCase.execute(threadID: threadID)
        stateStore.setMessages(messages, for: threadID)
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
            "发送对话开始，thread=\(shortID(threadID)), patient=\(shortID(patientContextStore.context.selectedMemberID)), length=\(draft.count)",
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
                patientID: patientContextStore.context.selectedMemberID,
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
                onAssistantPartial: { answer, reasoning, kind in
                    await MainActor.run {
                        stateStore.updateStreamingAssistant(
                            threadID: threadID,
                            kind: kind,
                            content: answer,
                            reasoningContent: reasoning
                        )
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

    private func shortID(_ value: UUID?) -> String {
        guard let value else { return "-" }
        return String(value.uuidString.prefix(8))
    }

    private func shortID(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(value)
    }
}
