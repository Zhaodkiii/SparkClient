import Combine
import Foundation
import UIKit

@MainActor
final class DeepTutorChatViewModel: ObservableObject {
    @Published private(set) var state: DeepTutorConversationState = .initial
    @Published private(set) var conversation: DeepTutorConversation?
    @Published private(set) var conversations: [DeepTutorConversationListItem] = []
    @Published private(set) var isCreatingConversation = false
    @Published private(set) var conversationCreationError: String?
    @Published var selectedConversationID: UUID?
    @Published private(set) var isQuizInlineInputFocused = false
    @Published private(set) var composerAttachmentDrafts: [DeepTutorComposerAttachmentDraft] = []

    var composerFileTransferService: FileTransferService { fileTransferService }

    private let repository: any DeepTutorLocalChatRepository
    private let loadMessagesUseCase: LoadDeepTutorMessagesUseCase
    private let loadConversationsUseCase: LoadDeepTutorConversationsUseCase
    private let createConversationUseCase: CreateDeepTutorConversationUseCase
    private let generateTitleUseCase: GenerateDeepTutorConversationTitleUseCase
    private let quizJudgeUseCase: DeepTutorQuizJudgeUseCase
    private let sendMessageUseCase: SendDeepTutorAIMessageUseCase
    private let localSendMessageUseCase: SendLocalDeepTutorMessageUseCase
    private let attachmentUploadUseCase: DeepTutorAttachmentUploadUseCase
    private let fileTransferService: FileTransferService
    private let toolInteractionCoordinatorStorage: ToolInteractionCoordinator
    private let memberContextStore: MemberContextStore
    private let logger: Logger
    private var activeConversationID: UUID?
    private let messagePageSize = 50
    private var cancellables = Set<AnyCancellable>()
    private var allMessagesCache: [DeepTutorMessage] = []
    private var isSendingMessage = false
    private var generationSession: DeepTutorGenerationSession?
    private var lastTracePhaseLogByMessageID: [UUID: String] = [:]
    private var pendingDatabaseReloadReason: String?
    private var submittedAskUserKeys: Set<String> = []
    private var submittedMemberSelectionKeys: Set<String> = []
    private var openTasks: [UUID: Task<Void, Never>] = [:]
    private var reloadTasks: [UUID: Task<Void, Never>] = [:]
    private var openGenerationByConversationID: [UUID: UInt64] = [:]
    private var reloadGenerationByConversationID: [UUID: UInt64] = [:]
    private var pendingDatabaseReloadTask: Task<Void, Never>?
    private var titleGenerationTasks: [UUID: Task<Void, Never>] = [:]
    private var titleGenerationGenerationByConversationID: [UUID: UInt64] = [:]
    private let publishGate = DeepTutorPublishGate()
    private var pendingConversationListRefreshTask: Task<Void, Never>?

    var toolInteractionCoordinator: ToolInteractionCoordinator { toolInteractionCoordinatorStorage }
    var availableMembers: [Member] { memberContextStore.context.members }

    var displayConversationTitle: String {
        DeepTutorSessionTitle.displayTitle(conversation?.title)
    }

    init(
        repository: any DeepTutorLocalChatRepository,
        chatOrchestrator: ChatOrchestrator,
        aiConfigCenter: AIConfigCenter,
        toolInteractionCoordinator: ToolInteractionCoordinator,
        memberContextStore: MemberContextStore,
        fileTransferService: FileTransferService,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.logger = logger
        self.fileTransferService = fileTransferService
        self.toolInteractionCoordinatorStorage = toolInteractionCoordinator
        self.memberContextStore = memberContextStore
        self.loadMessagesUseCase = LoadDeepTutorMessagesUseCase(repository: repository)
        self.loadConversationsUseCase = LoadDeepTutorConversationsUseCase(repository: repository)
        self.createConversationUseCase = CreateDeepTutorConversationUseCase(repository: repository)
        self.generateTitleUseCase = GenerateDeepTutorConversationTitleUseCase(
            repository: repository,
            orchestrator: chatOrchestrator,
            aiConfigCenter: aiConfigCenter,
            logger: logger
        )
        self.quizJudgeUseCase = DeepTutorQuizJudgeUseCase(
            orchestrator: chatOrchestrator,
            aiConfigCenter: aiConfigCenter
        )
        self.localSendMessageUseCase = SendLocalDeepTutorMessageUseCase(repository: repository, logger: logger)
        self.sendMessageUseCase = SendDeepTutorAIMessageUseCase(
            repository: repository,
            adapter: DeepTutorAIRuntimeAdapter(
                orchestrator: chatOrchestrator,
                aiConfigCenter: aiConfigCenter,
                logger: logger
            ),
            toolInteractionCoordinator: toolInteractionCoordinator,
            logger: logger
        )
        self.attachmentUploadUseCase = DeepTutorAttachmentUploadUseCase(fileTransferService: fileTransferService)

        NotificationCenter.default.publisher(for: .deepTutorChatDatabaseDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                self.handleDatabaseChange(note.deepTutorConversationChangeEvent)
            }
            .store(in: &cancellables)
    }

    func loadConversationsIfNeeded() async {
        DeepTutorChatLog.listLoadStart(source: "initial")
        let loaded = await loadConversationsUseCase()
        assignConversations(loaded, source: "initial")
        DeepTutorChatLog.listLoadDone(count: conversations.count, source: "initial")
        DeepTutorChatLog.conversationListLoaded(count: conversations.count)
    }

    func refreshConversations(source: String = "manual", expectedCreatedID: UUID? = nil) async {
        DeepTutorChatLog.listLoadStart(source: source)
        let previous = conversations
        let loaded = await loadConversationsUseCase()

        if let expectedCreatedID {
            let containsCreated = loaded.contains { $0.id == expectedCreatedID }
            let nextConversations: [DeepTutorConversationListItem]
            if containsCreated {
                nextConversations = loaded
            } else {
                logger.warning(
                    "create_refresh_missing_created_conversation id=\(DeepTutorChatLog.shortID(expectedCreatedID)), refreshCount=\(loaded.count), scenario=\(DeepTutorScenarioConstants.scenario)",
                    module: DeepTutorChatLog.module
                )
                if let optimistic = previous.first(where: { $0.id == expectedCreatedID }) {
                    nextConversations = [optimistic] + loaded.filter { $0.id != expectedCreatedID }
                } else {
                    nextConversations = loaded
                }
            }
            let changed = previous != nextConversations
            assignConversations(nextConversations, source: source)
            DeepTutorChatLog.conversationListRefreshed(
                count: conversations.count,
                source: source,
                changed: changed,
                containsCreated: containsCreated
            )
        } else {
            if loaded.isEmpty, previous.isEmpty == false {
                logger.warning(
                    "refresh_unexpected_empty_list source=\(source), previousCount=\(previous.count), scenario=\(DeepTutorScenarioConstants.scenario)",
                    module: DeepTutorChatLog.module
                )
                assignConversations(loaded, source: source)
                DeepTutorChatLog.conversationListRefreshed(
                    count: conversations.count,
                    source: source,
                    changed: true
                )
            } else {
                let changed = previous != loaded
                assignConversations(loaded, source: source)
                DeepTutorChatLog.conversationListRefreshed(
                    count: conversations.count,
                    source: source,
                    changed: changed
                )
            }
        }
        DeepTutorChatLog.listLoadDone(count: conversations.count, source: source)
    }

    private func optimisticallyInsertConversation(_ conversation: DeepTutorConversation) {
        let item = DeepTutorConversationListItem(
            id: conversation.id,
            conversation: conversation,
            latestPreview: "",
            latestMessageAt: conversation.updatedAt
        )
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(item, at: 0)
    }

    @discardableResult
    func createConversation(title: String = DeepTutorSessionTitle.defaultSentinel, refreshList: Bool = true) async throws -> DeepTutorConversation {
        let created = try await createConversationUseCase(title: title)
        if refreshList {
            await refreshConversations(source: "create")
        }
        return created
    }

    func createAndOpenConversation(source: String = "toolbar") async {
        let start = Date()
        logger.info(
            "新建 DeepTutor 对话开始，source=\(DeepTutorChatLog.createSourceLabel(source))",
            module: DeepTutorChatLog.module
        )

        isCreatingConversation = true
        conversationCreationError = nil
        defer { isCreatingConversation = false }

        do {
            let created = try await createConversation(title: DeepTutorSessionTitle.defaultSentinel, refreshList: false)
            DeepTutorChatLog.titlePlaceholderCreated(
                conversationID: created.id,
                rawTitle: created.title,
                displayTitle: DeepTutorSessionTitle.displayTitle(created.title)
            )
            optimisticallyInsertConversation(created)

            if let verified = await repository.loadConversation(id: created.id) {
                logger.info(
                    "新建 DeepTutor 对话写库校验通过，conversation=\(DeepTutorChatLog.shortID(created.id)), title=\(verified.title), scenario=\(DeepTutorScenarioConstants.scenario)",
                    module: DeepTutorChatLog.module
                )
            } else {
                logger.error(
                    "create_verify_missing_conversation id=\(DeepTutorChatLog.shortID(created.id)), scenario=\(DeepTutorScenarioConstants.scenario)",
                    module: DeepTutorChatLog.module
                )
                conversationCreationError = "对话已创建但本地数据库校验失败，请下拉刷新后重试"
                return
            }

            selectedConversationID = created.id
            await refreshConversations(source: "create", expectedCreatedID: created.id)
            await openConversation(created.id)
            let cost = Date().timeIntervalSince(start)
            logger.info(
                "新建 DeepTutor 对话完成，conversation=\(DeepTutorChatLog.shortID(created.id)), cost=\(DeepTutorChatLog.format(cost))s",
                module: DeepTutorChatLog.module
            )
        } catch {
            let cost = Date().timeIntervalSince(start)
            logger.error(
                "新建 DeepTutor 对话失败，cost=\(DeepTutorChatLog.format(cost))s error=\(error.localizedDescription)",
                module: DeepTutorChatLog.module
            )
            conversationCreationError = error.localizedDescription
        }
    }

    func openConversation(_ conversationID: UUID) async {
        if shouldSkipOpen(conversationID) {
            if let existing = openTasks[conversationID] {
                let generation = openGenerationByConversationID[conversationID] ?? 0
                DeepTutorChatLog.conversationOpenJoin(conversationID: conversationID, generation: generation)
                await existing.value
            } else {
                logger.debug(
                    "deeptutor.conversation.open.skip conversation=\(DeepTutorChatLog.shortID(conversationID)) reason=already_active phase=\(state.phase)",
                    module: DeepTutorChatLog.module
                )
            }
            return
        }

        if let existing = openTasks[conversationID] {
            let generation = openGenerationByConversationID[conversationID] ?? 0
            DeepTutorChatLog.conversationOpenJoin(conversationID: conversationID, generation: generation)
            await existing.value
            return
        }

        setQuizInlineInputFocused(false)

        let generation = (openGenerationByConversationID[conversationID] ?? 0) + 1
        openGenerationByConversationID[conversationID] = generation

        let task = Task { @MainActor in
            await performOpenConversation(conversationID, generation: generation)
        }
        openTasks[conversationID] = task
        await task.value
        if openGenerationByConversationID[conversationID] == generation {
            openTasks.removeValue(forKey: conversationID)
        }
    }

    private func performOpenConversation(_ conversationID: UUID, generation: UInt64) async {
        DeepTutorChatLog.conversationOpenStart(conversationID: conversationID)
        activeConversationID = conversationID
        guard let loadedConversation = await repository.loadConversation(id: conversationID) else {
            guard isCurrentOpenGeneration(conversationID, generation) else {
                DeepTutorChatLog.conversationOpenStaleDrop(conversationID: conversationID, generation: generation)
                return
            }
            logger.error(
                "打开 DeepTutor 对话失败：对话不存在或已删除，conversation=\(DeepTutorChatLog.shortID(conversationID))",
                module: DeepTutorChatLog.module
            )
            conversation = nil
            state.phase = .error("对话不存在或已被删除")
            return
        }

        guard isCurrentOpenGeneration(conversationID, generation) else {
            DeepTutorChatLog.conversationOpenStaleDrop(conversationID: conversationID, generation: generation)
            return
        }

        conversation = loadedConversation
        var next = state
        next.draftText = DeepTutorDraftStore.loadDraft(for: conversationID)
        next.activeCapability = .chat
        next.phase = .loadingLocal
        state = next

        let shouldLockBottom = DeepTutorScrollPositionStore.load(for: conversationID) == nil
        await reloadMessages(for: conversationID, lockBottom: shouldLockBottom, source: "open")

        guard isCurrentOpenGeneration(conversationID, generation) else {
            DeepTutorChatLog.conversationOpenStaleDrop(conversationID: conversationID, generation: generation)
            return
        }
        guard activeConversationID == conversationID else { return }

        state.phase = .ready
        DeepTutorChatLog.conversationOpenDone(
            conversationID: conversationID,
            messageCount: state.messages.count,
            cachedCount: allMessagesCache.count,
            hasMore: state.hasMoreMessages
        )
    }

    private func isCurrentOpenGeneration(_ conversationID: UUID, _ generation: UInt64) -> Bool {
        openGenerationByConversationID[conversationID] == generation
    }

    private func isCurrentReloadGeneration(_ conversationID: UUID, _ generation: UInt64) -> Bool {
        reloadGenerationByConversationID[conversationID] == generation
    }

    private func shouldSkipOpen(_ conversationID: UUID) -> Bool {
        activeConversationID == conversationID
            && conversation?.id == conversationID
            && (state.phase == .ready || state.phase == .loadingLocal)
    }

    func clearConversationCreationError() {
        conversationCreationError = nil
    }

    func resetForSessionSwitch() {
        activeConversationID = nil
        conversation = nil
        conversations = []
        allMessagesCache = []
        isCreatingConversation = false
        conversationCreationError = nil
        selectedConversationID = nil
        isSendingMessage = false
        lastTracePhaseLogByMessageID = [:]
        pendingDatabaseReloadReason = nil
        submittedAskUserKeys = []
        submittedMemberSelectionKeys = []
        openTasks.values.forEach { $0.cancel() }
        openTasks = [:]
        reloadTasks.values.forEach { $0.cancel() }
        reloadTasks = [:]
        openGenerationByConversationID = [:]
        reloadGenerationByConversationID = [:]
        pendingDatabaseReloadTask?.cancel()
        pendingDatabaseReloadTask = nil
        pendingConversationListRefreshTask?.cancel()
        pendingConversationListRefreshTask = nil
        titleGenerationTasks.values.forEach { $0.cancel() }
        titleGenerationTasks = [:]
        titleGenerationGenerationByConversationID = [:]
        state = .initial
    }

    func editUserMessage(messageID: UUID, newText: String) async {
        guard let conversationID = activeConversationID else { return }
        do {
            let branch = try await sendMessageUseCase.editUserMessage(
                conversationID: conversationID,
                messageID: messageID,
                newText: newText
            )
            let parentKey = branch.parentMessageID ?? messageID
            let siblings = await siblingMessages(for: parentKey, conversationID: conversationID)
            let newIndex = siblings.firstIndex(where: { $0.id == branch.id }) ?? siblings.count - 1
            state.selectedBranches = state.selectedBranches.selecting(branchIndex: newIndex, for: parentKey)
            await reloadMessages(for: conversationID)
        } catch {
            state.phase = .error(error.localizedDescription)
        }
    }

    func selectBranch(parentMessageID: UUID, branchIndex: Int) {
        publishGate.deferPublish(source: "select_branch") {
            var next = self.state
            next.selectedBranches = next.selectedBranches.selecting(branchIndex: branchIndex, for: parentMessageID)
            next.messages = self.visibleMessages(from: self.allMessagesCache)
            self.state = next
        }
    }

    func branchInfo(for messageID: UUID) -> (index: Int, count: Int)? {
        guard let message = allMessagesCache.first(where: { $0.id == messageID }) else { return nil }
        let parentKey = message.parentMessageID ?? message.id
        let siblings = siblingMessages(for: parentKey, in: allMessagesCache)
        guard siblings.count > 1 else { return nil }
        let index = siblings.firstIndex(where: { $0.id == messageID }) ?? 0
        return (index, siblings.count)
    }

    func rememberScrollAnchor(messageID: UUID?) {
        guard let conversationID = activeConversationID else { return }
        DeepTutorScrollPositionStore.save(anchorMessageID: messageID, for: conversationID)
    }

    private func siblingMessages(for parentKey: UUID, in messages: [DeepTutorMessage]) -> [DeepTutorMessage] {
        messages.filter {
            $0.role == .user && ($0.parentMessageID == parentKey || $0.id == parentKey)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    private func siblingMessages(for parentKey: UUID, conversationID: UUID) async -> [DeepTutorMessage] {
        siblingMessages(for: parentKey, in: allMessagesCache)
    }

    func reloadMessages(
        for conversationID: UUID,
        lockBottom: Bool = false,
        forceFullRediff: Bool = false,
        source: String = "manual"
    ) async {
        if let existing = reloadTasks[conversationID] {
            let generation = reloadGenerationByConversationID[conversationID] ?? 0
            DeepTutorChatLog.messagesReloadJoin(conversationID: conversationID, source: source, generation: generation)
            await existing.value
            return
        }

        let generation = (reloadGenerationByConversationID[conversationID] ?? 0) + 1
        reloadGenerationByConversationID[conversationID] = generation

        let task = Task { @MainActor in
            await performReloadMessages(
                for: conversationID,
                lockBottom: lockBottom,
                forceFullRediff: forceFullRediff,
                source: source,
                generation: generation
            )
        }
        reloadTasks[conversationID] = task
        await task.value
        if reloadGenerationByConversationID[conversationID] == generation {
            reloadTasks.removeValue(forKey: conversationID)
        }
    }

    private func performReloadMessages(
        for conversationID: UUID,
        lockBottom: Bool,
        forceFullRediff: Bool,
        source: String,
        generation: UInt64
    ) async {
        let start = Date()
        DeepTutorChatLog.messagesReloadStart(
            conversationID: conversationID,
            lockBottom: lockBottom,
            forceFullRediff: forceFullRediff,
            source: source
        )
        let totalCount = await repository.countMessages(conversationID: conversationID)
        let loaded = await loadMessagesUseCase(conversationID: conversationID, limit: messagePageSize, before: nil)
        let loadedAll = await loadMessagesUseCase(conversationID: conversationID, limit: nil, before: nil)
        let mergedAll = DeepTutorMessageReloadMerger.merge(
            reloaded: loadedAll,
            cached: allMessagesCache,
            conversationID: conversationID
        )
        let recoveredAll = DeepTutorMemberSelectionReloadRecovery.expireStalePendingBlocks(in: mergedAll)
        for message in recoveredAll {
            if let original = mergedAll.first(where: { $0.id == message.id }), original != message {
                _ = try? await repository.upsertMessage(message)
            }
        }
        allMessagesCache = recoveredAll
        let mergedPage = DeepTutorMessageReloadMerger.merge(
            reloaded: loaded,
            cached: mergedAll,
            conversationID: conversationID
        )
        let visible = visibleMessages(from: mergedPage)
        let visibleAll = visibleMessages(from: allMessagesCache)

        guard isCurrentReloadGeneration(conversationID, generation) else {
            DeepTutorChatLog.messagesReloadStaleDrop(conversationID: conversationID, source: source, generation: generation)
            return
        }
        guard activeConversationID == conversationID else {
            DeepTutorChatLog.messagesReloadStaleDrop(conversationID: conversationID, source: source, generation: generation)
            return
        }

        if totalCount > 0, loaded.isEmpty {
            logger.error(
                "deeptutor.messages.reload.empty_after_load conversation=\(DeepTutorChatLog.shortID(conversationID)) totalCount=\(totalCount) pageLoaded=0 allLoaded=\(allMessagesCache.count)",
                module: DeepTutorChatLog.module
            )
        } else if loaded.isEmpty, visible.isEmpty {
            logger.warning(
                "deeptutor.messages.reload.empty conversation=\(DeepTutorChatLog.shortID(conversationID)) totalCount=\(totalCount)",
                module: DeepTutorChatLog.module
            )
        }
        if visible.isEmpty, loaded.isEmpty == false {
            logger.warning(
                "deeptutor.messages.reload.visible_empty conversation=\(DeepTutorChatLog.shortID(conversationID)) loaded=\(loaded.count) allLoaded=\(allMessagesCache.count) visibleAll=\(visibleAll.count) selectedBranches=\(state.selectedBranches)",
                module: DeepTutorChatLog.module
            )
        }

        publishGate.deferPublish(source: source) {
            var latest = self.state
            latest.messages = visible
            latest.hasMoreMessages = totalCount > visible.count
            latest.isStreaming = visible.last?.status == .streaming
            if lockBottom {
                latest.lockBottomViewport = true
                latest.scrollToBottomRequestGeneration &+= 1
            }
            self.state = latest
        }

        let cost = Date().timeIntervalSince(start)
        DeepTutorChatLog.refreshReloadCompleted(
            conversationID: conversationID,
            source: source,
            totalCount: totalCount,
            visible: visible.count,
            messageCount: visible.count,
            isStreaming: state.isStreaming,
            durationMs: Int(cost * 1000)
        )
    }

    func loadMoreHistory(for conversationID: UUID) async {
        guard state.hasMoreMessages, let oldest = state.messages.first else { return }
        let older = await loadMessagesUseCase(
            conversationID: conversationID,
            limit: messagePageSize,
            before: oldest.createdAt
        )
        guard older.isEmpty == false else {
            publishGate.deferPublish(source: "load_more") {
                self.state.hasMoreMessages = false
            }
            return
        }
        let merged = visibleMessages(from: older + state.messages)
        let totalCount = await repository.countMessages(conversationID: conversationID)
        publishGate.deferPublish(source: "load_more") {
            var next = self.state
            next.messages = merged
            next.hasMoreMessages = totalCount > merged.count
            self.state = next
        }
    }

    func updateDraft(_ text: String) {
        state.draftText = text
        if let activeConversationID {
            DeepTutorDraftStore.saveDraft(text, for: activeConversationID)
        }
    }

    func handleAttachmentsPicked(_ files: [MedicalUploadLocalFile]) {
        guard state.isStreaming == false else { return }
        DeepTutorAttachmentDiagnostics.pickStart(source: "paperclip")
        Task {
            let remainingSlots = max(0, DeepTutorAttachmentMapper.maxComposerAttachments - composerAttachmentDrafts.count)
            guard remainingSlots > 0 else { return }
            let drafts = await DeepTutorAttachmentMapper.makeDrafts(from: Array(files.prefix(remainingSlots)))
            await MainActor.run {
                composerAttachmentDrafts.append(contentsOf: drafts)
                DeepTutorAttachmentDiagnostics.pickDone(drafts)
            }
        }
    }

    func uploadComposerAttachment(id: UUID) {
        guard let index = composerAttachmentDrafts.firstIndex(where: { $0.id == id }) else { return }
        composerAttachmentDrafts[index].phase = .uploading
        composerAttachmentDrafts[index].uploadProgress = 0
        composerAttachmentDrafts[index].errorMessage = nil
        let draft = composerAttachmentDrafts[index]
        DeepTutorAttachmentDiagnostics.uploadStart(draftID: id, filename: draft.displayName)
        let start = Date()

        Task {
            do {
                let uploaded = try await attachmentUploadUseCase.upload(draft: draft) { [weak self] progress in
                    Task { @MainActor in
                        guard let self,
                              let currentIndex = self.composerAttachmentDrafts.firstIndex(where: { $0.id == id }) else { return }
                        self.composerAttachmentDrafts[currentIndex].uploadProgress = progress
                        DeepTutorAttachmentDiagnostics.uploadProgress(draftID: id, progress: progress)
                    }
                }
                await MainActor.run {
                    guard let currentIndex = composerAttachmentDrafts.firstIndex(where: { $0.id == id }) else { return }
                    composerAttachmentDrafts[currentIndex].phase = .uploaded
                    composerAttachmentDrafts[currentIndex].uploadProgress = 1
                    composerAttachmentDrafts[currentIndex].uploaded = uploaded
                    let durationMs = Int(Date().timeIntervalSince(start) * 1000)
                    DeepTutorAttachmentDiagnostics.uploadDone(draftID: id, uploaded: uploaded, durationMs: durationMs)
                }
            } catch {
                await MainActor.run {
                    guard let currentIndex = composerAttachmentDrafts.firstIndex(where: { $0.id == id }) else { return }
                    composerAttachmentDrafts[currentIndex].phase = .failed
                    composerAttachmentDrafts[currentIndex].errorMessage = error.localizedDescription
                    DeepTutorAttachmentDiagnostics.uploadFailed(draftID: id, error: error.localizedDescription)
                }
            }
        }
    }

    func retryComposerAttachmentUpload(id: UUID) {
        uploadComposerAttachment(id: id)
    }

    func removeComposerAttachment(id: UUID) {
        composerAttachmentDrafts.removeAll { $0.id == id }
    }

    private func clearComposerAttachments() {
        composerAttachmentDrafts = []
    }

    private var uploadedComposerAttachments: [DeepTutorAttachment] {
        composerAttachmentDrafts.compactMap { $0.uploaded?.persistedAttachment() }
    }

    private var canSendComposerMessage: Bool {
        let hasText = state.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasUploadedAttachment = composerAttachmentDrafts.contains { $0.phase == .uploaded }
        let hasBlockingAttachment = composerAttachmentDrafts.contains(where: \.isBlockingSend)
        return state.isStreaming == false
            && hasBlockingAttachment == false
            && (hasText || hasUploadedAttachment)
    }

    func updateCapability(_ capability: DeepTutorCapability) {
        let previous = state.activeCapability
        state.activeCapability = capability
        state.enabledOptionalTools = DeepTutorUserToolSettingsStore.enabledToolsForCapability(capability)
        if let conversationID = activeConversationID {
            DeepTutorChatLog.capabilitySelected(
                conversationID: conversationID,
                selected: capability.rawValue,
                previous: previous.rawValue
            )
            DeepTutorChatLog.toolPolicyManifest(
                conversationID: conversationID,
                capability: capability,
                enabledTools: state.enabledOptionalTools
            )
        }
    }

    func setQuizInlineInputFocused(_ focused: Bool) {
        guard isQuizInlineInputFocused != focused else { return }
        isQuizInlineInputFocused = focused
        if let conversationID = activeConversationID {
            if focused {
                DeepTutorChatLog.composerHiddenForInlineInput(conversationID: conversationID)
            } else {
                DeepTutorChatLog.composerRestoredAfterInlineInput(conversationID: conversationID)
            }
        }
    }

    func startQuizFollowUp(prefill: String) {
        state.activeCapability = .chat
        state.draftText = prefill
        setQuizInlineInputFocused(false)
    }

    func judgeQuizAnswer(question: DeepTutorQuizQuestion, userAnswer: String) async -> String? {
        guard let conversationID = activeConversationID else { return nil }
        let settings = conversation?.generationSettings ?? .default
        do {
            return try await quizJudgeUseCase(
                DeepTutorQuizJudgeUseCase.Request(
                    conversationID: conversationID,
                    question: question,
                    userAnswer: userAnswer,
                    preferredModelName: settings.currentModelName
                )
            )
        } catch {
            logger.warning(
                "DeepTutor quiz judge failed: \(error.localizedDescription)",
                module: DeepTutorChatLog.module
            )
            return nil
        }
    }

    func sendMessage() async {
        let start = Date()

        guard let conversationID = activeConversationID else {
            logger.warning("发送 DeepTutor 对话跳过：当前没有打开的会话", module: DeepTutorChatLog.module)
            return
        }
        let text = state.draftText
        let attachments = uploadedComposerAttachments
        guard canSendComposerMessage else {
            logger.warning("发送 DeepTutor 对话跳过：输入内容为空或附件未就绪", module: DeepTutorChatLog.module)
            return
        }

        let effectiveText = DeepTutorAttachmentSendTextBuilder.effectiveSendText(
            userText: text,
            attachments: attachments
        )
        let hasUserText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        DeepTutorAttachmentDiagnostics.sendBuild(
            count: attachments.count,
            imageCount: attachments.filter { $0.type == "image" }.count,
            fileCount: attachments.filter { $0.type == "pdf" || $0.type == "file" }.count,
            hasText: hasUserText
        )

        setQuizInlineInputFocused(false)

        let effectiveCapability = state.activeCapability
        DeepTutorChatLog.capabilityResolved(
            conversationID: conversationID,
            selected: state.activeCapability.rawValue,
            effective: effectiveCapability.rawValue,
            requestSnapshot: effectiveCapability.rawValue,
            messageCapability: effectiveCapability.rawValue,
            source: "send"
        )

        logger.info(
            "发送 DeepTutor 对话开始，conversation=\(DeepTutorChatLog.shortID(conversationID)), capability=\(effectiveCapability.rawValue), userContent=\(DeepTutorChatLog.contentSnippet(text))",
            module: DeepTutorChatLog.module
        )

        state.draftText = ""
        clearComposerAttachments()
        DeepTutorDraftStore.saveDraft("", for: conversationID)
        state.phase = .streaming
        state.isStreaming = true
        state.lockBottomViewport = true
        state.scrollToBottomRequestGeneration &+= 1
        isSendingMessage = true
        defer {
            isSendingMessage = false
            generationSession = nil
        }

        let session = DeepTutorGenerationSession()
        generationSession = session
        let settings = conversation?.generationSettings ?? .default
        let title = promptConversationTitle()
        let history = visibleMessages(from: allMessagesCache)
        let onStreamingUpdate = makeStreamingUpdateHandler()

        do {
            let result: (user: DeepTutorMessage, assistant: DeepTutorMessage)
            if DeepTutorDebugFlags.useLocalSimulator {
                result = try await localSendMessageUseCase(
                    conversationID: conversationID,
                    text: text,
                    capability: effectiveCapability,
                    onStreamingUpdate: onStreamingUpdate
                )
            } else {
                let requestedTools = state.enabledOptionalTools
                result = try await sendMessageUseCase(
                    conversationID: conversationID,
                    text: effectiveText,
                    capability: effectiveCapability,
                    conversationTitle: title,
                    settings: settings,
                    visibleHistory: history,
                    session: session,
                    boundMemberID: conversation?.memberID,
                    requestedCanonicalTools: requestedTools,
                    attachments: attachments,
                    onStreamingUpdate: onStreamingUpdate
                )
            }
            state.phase = .ready
            state.isStreaming = false
            state.lockBottomViewport = false
            await reloadMessagesAfterGeneration(for: conversationID)
            maybeGenerateConversationTitle(conversationID: conversationID, isRegenerate: false)
            await refreshConversations(source: "send")
            let cost = Date().timeIntervalSince(start)
            let durationMs = Int(cost * 1000)
            DeepTutorChatLog.messageSendDone(
                conversationID: conversationID,
                userMessageID: result.user.id,
                assistantMessageID: result.assistant.id,
                durationMs: durationMs
            )
            logger.info(
                "发送 DeepTutor 对话完成，conversation=\(DeepTutorChatLog.shortID(conversationID)), userMessage=\(DeepTutorChatLog.shortID(result.user.id)), userStatus=\(DeepTutorChatLog.statusLabel(result.user.status)), userContent=\(DeepTutorChatLog.contentSnippet(result.user.content)), assistantMessage=\(DeepTutorChatLog.shortID(result.assistant.id)), assistantStatus=\(DeepTutorChatLog.statusLabel(result.assistant.status)), assistantContent=\(DeepTutorChatLog.contentSnippet(result.assistant.content)), messages=\(state.messages.count), cost=\(DeepTutorChatLog.format(cost))s",
                module: DeepTutorChatLog.module
            )
        } catch {
            let cost = Date().timeIntervalSince(start)
            let message = DeepTutorRuntimeRequestBuilder.userFacingConfigError(error)
            DeepTutorChatLog.messageSendFailed(conversationID: conversationID, error: message)
            logger.error(
                "发送 DeepTutor 对话失败，cost=\(DeepTutorChatLog.format(cost))s error=\(message)",
                module: DeepTutorChatLog.module
            )
            state.phase = .error(message)
            state.isStreaming = false
            await reloadMessages(for: conversationID)
        }
    }

    func retryMessage(_ message: DeepTutorMessage) async {
        guard let conversationID = activeConversationID else { return }
        guard message.role == .assistant, message.status == .failed else { return }
        guard let userMessage = precedingUserMessage(for: message, in: allMessagesCache) else { return }

        state.phase = .streaming
        state.isStreaming = true
        isSendingMessage = true
        let session = DeepTutorGenerationSession()
        generationSession = session
        defer {
            isSendingMessage = false
            generationSession = nil
            state.isStreaming = false
            state.phase = .ready
        }

        do {
            DeepTutorChatLog.capabilityResolved(
                conversationID: conversationID,
                selected: state.activeCapability.rawValue,
                effective: message.capability.rawValue,
                requestSnapshot: userMessage.requestSnapshot?.capability?.rawValue,
                messageCapability: message.capability.rawValue,
                source: "retry"
            )
            _ = try await sendMessageUseCase.retryAssistant(
                conversationID: conversationID,
                assistantMessageID: message.id,
                userMessageID: userMessage.id,
                capability: message.capability,
                conversationTitle: promptConversationTitle(),
                settings: conversation?.generationSettings ?? .default,
                visibleHistory: visibleMessages(from: allMessagesCache),
                session: session,
                onStreamingUpdate: makeStreamingUpdateHandler()
            )
            await reloadMessagesAfterGeneration(for: conversationID)
            maybeGenerateConversationTitle(conversationID: conversationID, isRegenerate: false)
            await refreshConversations(source: "retry")
        } catch {
            state.phase = .error(DeepTutorRuntimeRequestBuilder.userFacingConfigError(error))
        }
    }

    func regenerateMessage(_ message: DeepTutorMessage) async {
        guard let conversationID = activeConversationID else { return }
        guard message.role == .assistant else { return }
        guard let userMessage = precedingUserMessage(for: message, in: allMessagesCache) else { return }

        state.phase = .streaming
        state.isStreaming = true
        isSendingMessage = true
        let session = DeepTutorGenerationSession()
        generationSession = session
        defer {
            isSendingMessage = false
            generationSession = nil
            state.isStreaming = false
            state.phase = .ready
        }

        do {
            DeepTutorChatLog.capabilityResolved(
                conversationID: conversationID,
                selected: state.activeCapability.rawValue,
                effective: message.capability.rawValue,
                requestSnapshot: userMessage.requestSnapshot?.capability?.rawValue,
                messageCapability: message.capability.rawValue,
                source: "regenerate"
            )
            _ = try await sendMessageUseCase.regenerateAssistant(
                conversationID: conversationID,
                assistantMessageID: message.id,
                userMessageID: userMessage.id,
                capability: message.capability,
                conversationTitle: promptConversationTitle(),
                settings: conversation?.generationSettings ?? .default,
                visibleHistory: visibleMessages(from: allMessagesCache),
                session: session,
                onStreamingUpdate: makeStreamingUpdateHandler()
            )
            await reloadMessagesAfterGeneration(for: conversationID)
            await refreshConversations(source: "regenerate")
        } catch {
            state.phase = .error(DeepTutorRuntimeRequestBuilder.userFacingConfigError(error))
        }
    }

    private func precedingUserMessage(for assistant: DeepTutorMessage, in messages: [DeepTutorMessage]) -> DeepTutorMessage? {
        messages
            .filter { $0.role == .user && $0.createdAt <= assistant.createdAt }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    func submitAskUser(
        assistantMessageID: UUID,
        toolCallID: String,
        answers: [DeepTutorAskUserAnswer]
    ) async {
        guard let conversationID = activeConversationID else { return }
        let submitKey = DeepTutorAskUserIdentity.submitKey(
            assistantMessageID: assistantMessageID,
            toolCallID: toolCallID,
            answers: answers
        )
        if submittedAskUserKeys.contains(submitKey) {
            DeepTutorChatLog.askUserSubmitSkippedDuplicate(
                conversationID: conversationID,
                assistantMessageID: assistantMessageID,
                identityKey: submitKey,
                phase: state.phase.logLabel
            )
            return
        }
        submittedAskUserKeys.insert(submitKey)
        let start = Date()
        let answersSummary = answers.map(\.text).joined(separator: "|")
        logger.info(
            "提交 ask_user 开始，conversation=\(DeepTutorChatLog.shortID(conversationID)), message=\(DeepTutorChatLog.shortID(assistantMessageID)), answers=\(answersSummary)",
            module: DeepTutorChatLog.module
        )
        state.phase = .resolvingAskUser
        state.isStreaming = true
        isSendingMessage = true
        let session = DeepTutorGenerationSession()
        generationSession = session
        defer {
            isSendingMessage = false
            generationSession = nil
        }
        let settings = conversation?.generationSettings ?? .default
        let title = promptConversationTitle()
        let history = visibleMessages(from: allMessagesCache)
        let onStreamingUpdate = makeStreamingUpdateHandler()
        do {
            _ = try await sendMessageUseCase.submitAskUser(
                conversationID: conversationID,
                assistantMessageID: assistantMessageID,
                toolCallID: toolCallID,
                answers: answers,
                capability: state.activeCapability,
                conversationTitle: title,
                settings: settings,
                visibleHistory: history,
                session: session,
                onStreamingUpdate: onStreamingUpdate
            )
            state.phase = .ready
            state.isStreaming = false
            await reloadMessagesAfterGeneration(for: conversationID)
            maybeGenerateConversationTitle(conversationID: conversationID, isRegenerate: false)
            let cost = Date().timeIntervalSince(start)
            logger.info(
                "提交 ask_user 完成，conversation=\(DeepTutorChatLog.shortID(conversationID)), cost=\(DeepTutorChatLog.format(cost))s",
                module: DeepTutorChatLog.module
            )
        } catch {
            let cost = Date().timeIntervalSince(start)
            logger.error(
                "提交 ask_user 失败，cost=\(DeepTutorChatLog.format(cost))s error=\(error.localizedDescription)",
                module: DeepTutorChatLog.module
            )
            DeepTutorChatLog.askUserSubmitResumeFailed(
                conversationID: conversationID,
                assistantMessageID: assistantMessageID,
                toolCallID: toolCallID,
                error: error.localizedDescription
            )
            state.phase = .error(error.localizedDescription)
            state.isStreaming = false
        }
    }

    func submitMemberSelection(
        assistantMessageID: UUID,
        toolCallID: String,
        memberID: Int
    ) async {
        guard let conversationID = activeConversationID else { return }
        let submitKey = DeepTutorMemberSelectionIdentity.submitKey(
            assistantMessageID: assistantMessageID,
            toolCallID: toolCallID,
            memberID: memberID
        )
        if submittedMemberSelectionKeys.contains(submitKey) {
            return
        }
        submittedMemberSelectionKeys.insert(submitKey)

        let memberName = memberContextStore.context.members.first(where: { $0.id == memberID })?.name
            ?? L10n.text("chat.composer.member_profile.unknown")

        state.phase = .resolvingMemberSelection
        state.isStreaming = true
        isSendingMessage = true
        let session = DeepTutorGenerationSession()
        generationSession = session
        defer {
            isSendingMessage = false
            generationSession = nil
        }

        let settings = conversation?.generationSettings ?? .default
        let title = promptConversationTitle()
        let history = visibleMessages(from: allMessagesCache)
        let onStreamingUpdate = makeStreamingUpdateHandler()

        do {
            _ = try await sendMessageUseCase.submitMemberSelection(
                conversationID: conversationID,
                assistantMessageID: assistantMessageID,
                toolCallID: toolCallID,
                memberID: memberID,
                memberName: memberName,
                capability: state.activeCapability,
                conversationTitle: title,
                settings: settings,
                visibleHistory: history,
                session: session,
                onStreamingUpdate: onStreamingUpdate
            )
            memberContextStore.select(memberID: memberID)
            if var currentConversation = conversation {
                currentConversation.memberID = memberID
                conversation = currentConversation
            }
            state.phase = .ready
            state.isStreaming = false
            await reloadMessagesAfterGeneration(for: conversationID)
            maybeGenerateConversationTitle(conversationID: conversationID, isRegenerate: false)
        } catch {
            state.phase = .error(error.localizedDescription)
            state.isStreaming = false
        }
    }

    func stopStreaming() {
        let session = generationSession
        Task {
            await session?.cancel()
        }
        publishGate.deferPublish(source: "stop_streaming", priority: .immediate) {
            var next = self.state
            next.isStreaming = false
            next.phase = .ready
            self.state = next
        }
    }

    func releaseBottomLockAfterUserInteraction() {
        handleUserScrollInteraction()
    }

    func handleUserScrollInteraction() {
        publishGate.deferPublish(source: "scroll") {
            if self.state.lockBottomViewport {
                var next = self.state
                next.lockBottomViewport = false
                self.state = next
            }
            if let lastID = self.state.messages.last?.id {
                self.rememberScrollAnchor(messageID: lastID)
            }
        }
    }

    func makeMessageRowModels() -> [DeepTutorMessageRowModel] {
        guard let conversationID = activeConversationID else { return [] }
        let visible = state.messages
        let streamingTailID = visible.last(where: { $0.status == .streaming })?.clientMessageID
        return visible.map { message in
            let branchInfo = makeBranchInfo(for: message)
            let signature = DeepTutorMessageRowModelBuilder.makeRenderSignature(message: message)
            DeepTutorChatLog.messageRowModelBuilt(
                conversationID: conversationID,
                messageID: message.id,
                role: message.role.rawValue,
                signature: signature,
                branch: branchInfo.map { "\($0.index)/\($0.count)" } ?? "-"
            )
            return DeepTutorMessageRowModel(
                id: message.clientMessageID,
                conversationID: conversationID,
                message: message,
                branchInfo: branchInfo,
                isStreamingTail: message.clientMessageID == streamingTailID,
                renderSignature: signature
            )
        }
    }

    func handleRowCopy(messageID: UUID) {
        guard let message = allMessagesCache.first(where: { $0.id == messageID }) else { return }
        UIPasteboard.general.string = message.content
    }

    func handleRowEdit(messageID: UUID, newText: String) async {
        await editUserMessage(messageID: messageID, newText: newText)
    }

    func handleRowRetry(messageID: UUID) async {
        guard let message = allMessagesCache.first(where: { $0.id == messageID }) else { return }
        await retryMessage(message)
    }

    func handleRowSelectBranch(parentMessageID: UUID, branchIndex: Int) {
        selectBranch(parentMessageID: parentMessageID, branchIndex: branchIndex)
    }

    private func makeBranchInfo(for message: DeepTutorMessage) -> DeepTutorMessageBranchInfo? {
        guard message.role == .user else { return nil }
        guard let info = branchInfo(for: message.id) else { return nil }
        let parentKey = message.parentMessageID ?? message.id
        return DeepTutorMessageBranchInfo(
            index: info.index,
            count: info.count,
            parentMessageID: parentKey
        )
    }

    func allMessagesForDebugExport() -> [DeepTutorMessage] {
        allMessagesCache
    }

    func logDebugInfo(
        conversationID: UUID,
        pageContext: DeepTutorChatDebugPageContext
    ) {
        DeepTutorChatDebugExporter.logDebugInfo(
            viewModel: self,
            conversationID: conversationID,
            pageContext: pageContext,
            logger: logger
        )
    }

    private func applyStreamingMessage(_ message: DeepTutorMessage) {
        guard message.conversationID == activeConversationID else { return }
        let previous = allMessagesCache.first(where: { $0.id == message.id })
        if let index = allMessagesCache.firstIndex(where: { $0.id == message.id }) {
            allMessagesCache[index] = message
        } else {
            allMessagesCache.append(message)
            allMessagesCache.sort { $0.createdAt < $1.createdAt }
        }

        let priority = streamingCommitPriority(for: message, previous: previous)
        if priority == .reasoningCoalesce {
            DeepTutorChatLog.streamReasoningCoalesced(
                conversationID: message.conversationID,
                assistantMessageID: message.id,
                reasoningLen: reasoningLength(for: message),
                answerLen: message.content.count,
                intervalMs: 120
            )
        }

        publishGate.deferPublish(source: "stream", priority: priority) {
            self.commitStreamingUIState(for: message)
        }
    }

    private func commitStreamingUIState(for message: DeepTutorMessage) {
        var next = state
        next.messages = visibleMessages(from: allMessagesCache)
        next.isStreaming = message.status == .streaming || state.isStreaming
        if message.role == .user || message.status == .streaming {
            next.scrollToBottomRequestGeneration &+= 1
        }
        state = next

        if message.role == .assistant,
           let traceBlock = message.blocks.first(where: { $0.kind == .trace }),
           case .trace(let payload) = traceBlock.payload {
            let hasFinalContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let askUserCount = message.blocks.filter { $0.kind == .askUser }.count
            let traceKey = [
                "streaming=\(message.status == .streaming)",
                "final=\(hasFinalContent)",
                "phase=\(payload.isFinalAnswerPhase)",
                "ask=\(askUserCount)",
                "rows=\(payload.rows.count)",
            ].joined(separator: "|")
            if lastTracePhaseLogByMessageID[message.id] != traceKey {
                lastTracePhaseLogByMessageID[message.id] = traceKey
                let blockKinds = message.blocks.map { $0.kind.rawValue }.joined(separator: "|")
                DeepTutorChatLog.traceFinalPhase(
                    messageID: message.id,
                    isStreaming: message.status == .streaming,
                    hasFinalContent: hasFinalContent,
                    isFinalAnswerPhase: payload.isFinalAnswerPhase
                )
                logger.debug(
                    "deeptutor.trace.state_changed message=\(DeepTutorChatLog.shortID(message.id)) rows=\(payload.rows.count) askUserBlocks=\(askUserCount) blocks=\(blockKinds)",
                    module: DeepTutorChatLog.module
                )
            }
            if hasFinalContent || payload.isFinalAnswerPhase {
                DeepTutorChatLog.streamReasoningCommit(
                    conversationID: message.conversationID,
                    assistantMessageID: message.id,
                    reasoningLen: reasoningLength(for: message),
                    answerLen: message.content.count,
                    collapsed: payload.isFinalAnswerPhase
                )
            }
        }
    }

    private func streamingCommitPriority(
        for message: DeepTutorMessage,
        previous: DeepTutorMessage?
    ) -> DeepTutorPublishPriority {
        let hasFinal = message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let prevHadFinal = previous.map {
            $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } ?? false

        let hasAskUser = message.blocks.contains { $0.kind == .askUser }
        let prevHadAsk = previous?.blocks.contains { $0.kind == .askUser } ?? false
        if hasAskUser && !prevHadAsk {
            return .immediate
        }

        let hasMemberSelection = message.blocks.contains { $0.kind == .memberSelection }
        let prevHadMemberSelection = previous?.blocks.contains { $0.kind == .memberSelection } ?? false
        if hasMemberSelection && !prevHadMemberSelection {
            return .immediate
        }

        if hasFinal && !prevHadFinal {
            DeepTutorChatLog.streamAnswerPhaseEnter(
                conversationID: message.conversationID,
                assistantMessageID: message.id,
                answerLen: message.content.count
            )
            return .immediate
        }

        if message.role == .assistant && !hasFinal {
            return .reasoningCoalesce
        }

        return .normal
    }

    private func reasoningLength(for message: DeepTutorMessage) -> Int {
        if let traceBlock = message.blocks.first(where: { $0.kind == .trace }),
           case .trace(let payload) = traceBlock.payload {
            return payload.rows.compactMap(\.resultDetail).joined().count
        }
        return message.events.compactMap { event -> String? in
            switch event {
            case .reasoningDelta(let text, _, _):
                return text
            default:
                return nil
            }
        }.joined().count
    }

    private func makeStreamingUpdateHandler() -> @Sendable (DeepTutorMessage) async -> Void {
        { [weak self] message in
            await MainActor.run {
                self?.applyStreamingMessage(message)
            }
        }
    }

    private var shouldDeferMessageReload: Bool {
        isSendingMessage
            || state.isStreaming
            || state.phase == .streaming
            || state.phase == .resolvingAskUser
            || state.phase == .loadingLocal
            || generationSession != nil
    }

    private func reloadMessagesAfterGeneration(for conversationID: UUID) async {
        await reloadMessages(
            for: conversationID,
            lockBottom: true,
            source: "terminal_consistency"
        )
        if pendingDatabaseReloadReason != nil {
            pendingDatabaseReloadReason = nil
            DeepTutorChatLog.messagesReloadAppliedAfterStream(
                conversationID: conversationID,
                reason: "terminal_consistency",
                phase: state.phase.logLabel,
                isStreaming: state.isStreaming
            )
        }
    }

    private func handleDatabaseChange(_ event: DeepTutorConversationChangeEvent?) {
        if isCreatingConversation {
            return
        }

        guard let event else {
            scheduleDebouncedConversationListRefresh(source: "database_change")
            return
        }
        DeepTutorChatLog.databaseChangeReceived(
            conversationID: event.conversationID,
            affectsList: event.affectsConversationList,
            affectsMessages: event.conversationID == activeConversationID
        )
        if event.kind == .titleUpdated, let conversationID = event.conversationID {
            Task {
                if let updated = await repository.loadConversation(id: conversationID) {
                    await MainActor.run {
                        applyConversationTitleUpdate(updated, source: .autoGenerated, stage: "title")
                    }
                }
            }
            return
        }
        if event.affectsConversationList {
            scheduleDebouncedConversationListRefresh(source: "database_change")
        }
        guard let conversationID = event.conversationID, conversationID == activeConversationID else {
            return
        }

        if shouldDeferMessageReload {
            pendingDatabaseReloadReason = "database_change"
            DeepTutorChatLog.messagesReloadSkippedActiveStream(
                conversationID: conversationID,
                reason: "database_change",
                phase: state.phase.logLabel,
                isStreaming: state.isStreaming,
                activeAssistantMessage: generationSession != nil
                    ? allMessagesCache.last(where: { $0.role == .assistant && $0.status == .streaming })?.id
                    : nil
            )
            return
        }

        Task {
            pendingDatabaseReloadTask?.cancel()
            pendingDatabaseReloadTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await reloadMessages(for: conversationID, source: "database_change")
            }
        }
    }

    private func visibleMessages(from messages: [DeepTutorMessage]) -> [DeepTutorMessage] {
        let filtered = messages.filter { $0.role != .system && $0.isDeleted == false }
        return applyBranchSelection(to: filtered)
    }

    private func applyBranchSelection(to messages: [DeepTutorMessage]) -> [DeepTutorMessage] {
        let userMessages = messages.filter { $0.role == .user }
        let assistantMessages = messages.filter { $0.role == .assistant }.sorted { $0.createdAt < $1.createdAt }
        let roots = userMessages.filter { $0.parentMessageID == nil }.sorted { $0.createdAt < $1.createdAt }

        var result: [DeepTutorMessage] = []

        for (index, root) in roots.enumerated() {
            let parentKey = root.id
            let siblings = siblingMessages(for: parentKey, in: messages)
            let selectedIndex = state.selectedBranches.selectedIndex(for: parentKey)
            let selectedUser = siblings.indices.contains(selectedIndex) ? siblings[selectedIndex] : siblings.last ?? root
            result.append(selectedUser)

            let nextRootCreatedAt = index + 1 < roots.count ? roots[index + 1].createdAt : nil
            let lowerBound = selectedUser.createdAt
            let assistantsForTurn = assistantMessages.filter { assistant in
                assistant.createdAt >= lowerBound &&
                    (nextRootCreatedAt == nil || assistant.createdAt < nextRootCreatedAt!)
            }
            result.append(contentsOf: assistantsForTurn)
        }

        return result
    }

    private func promptConversationTitle() -> String {
        DeepTutorSessionTitle.titleForPrompt(conversation?.title)
            ?? DeepTutorSessionTitle.defaultSentinel
    }

    private func maybeGenerateConversationTitle(conversationID: UUID, isRegenerate: Bool) {
        titleGenerationTasks[conversationID]?.cancel()
        let generation = (titleGenerationGenerationByConversationID[conversationID] ?? 0) + 1
        titleGenerationGenerationByConversationID[conversationID] = generation

        let currentTitle = conversation?.title ?? DeepTutorSessionTitle.defaultSentinel
        let messages = allMessagesCache
        let preferredModel = conversation?.currentModelName

        titleGenerationTasks[conversationID] = Task { @MainActor in
            defer { titleGenerationTasks.removeValue(forKey: conversationID) }
            do {
                let request = GenerateDeepTutorConversationTitleUseCase.Request(
                    conversationID: conversationID,
                    messages: messages,
                    currentTitle: currentTitle,
                    isRegenerate: isRegenerate,
                    preferredModelName: preferredModel,
                    languageCode: Locale.current.language.languageCode?.identifier
                )
                guard let result = try await generateTitleUseCase(request) else { return }
                guard titleGenerationGenerationByConversationID[conversationID] == generation else {
                    DeepTutorChatLog.titleUIIgnoredStale(
                        conversationID: conversationID,
                        expectedGeneration: generation
                    )
                    return
                }
                applyConversationTitleUpdate(result.conversation, source: result.source, stage: "title")
            } catch {
                logger.warning(
                    "DeepTutor 会话标题生成失败，conversation=\(DeepTutorChatLog.shortID(conversationID)), error=\(error.localizedDescription)",
                    module: DeepTutorChatLog.module
                )
            }
        }
    }

    private func applyConversationTitleUpdate(
        _ updated: DeepTutorConversation,
        source: DeepTutorConversationTitleSource,
        stage: String
    ) {
        let navigationUpdated = activeConversationID == updated.id
        let listIndex = conversations.firstIndex(where: { $0.id == updated.id })
        let existingListItem = listIndex.map { conversations[$0] }
        publishGate.deferPublish(source: "title_update") {
            if navigationUpdated {
                self.conversation = updated
            }
            if let index = listIndex, let existing = existingListItem {
                self.conversations[index] = DeepTutorConversationListItem(
                    id: existing.id,
                    conversation: updated,
                    latestPreview: existing.latestPreview,
                    latestMessageAt: existing.latestMessageAt,
                    latestMessageStatus: existing.latestMessageStatus
                )
            }
        }
        DeepTutorChatLog.titleSessionMetaLocal(
            conversationID: updated.id,
            title: updated.title,
            source: source,
            activeConversation: navigationUpdated
        )
        DeepTutorChatLog.titleUIApplied(
            conversationID: updated.id,
            title: updated.title,
            navigationUpdated: navigationUpdated,
            listUpdated: listIndex != nil
        )
    }

    private func assignConversations(_ items: [DeepTutorConversationListItem], source: String) {
        publishGate.deferPublish(source: source) {
            self.conversations = items
        }
    }

    private func scheduleDebouncedConversationListRefresh(source: String) {
        if publishGate.isMessageListApplying {
            DeepTutorChatLog.databaseChangeDeferred(
                conversationID: activeConversationID,
                reason: "snapshot_applying"
            )
        }
        pendingConversationListRefreshTask?.cancel()
        let start = Date()
        pendingConversationListRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await refreshConversations(source: source)
            let delayMs = Int(Date().timeIntervalSince(start) * 1000)
            DeepTutorChatLog.databaseChangeCommit(
                conversationID: activeConversationID,
                delayMs: delayMs
            )
        }
    }
}

extension DeepTutorChatViewModel: DeepTutorMessageListRenderStateObserving {
    func messageListWillApplySnapshot(conversationID: UUID) {
        DeepTutorChatLog.cancelRefreshSummaryFallback(conversationID: conversationID)
        publishGate.isMessageListApplying = true
        DeepTutorChatLog.renderTransactionBegin(conversationID: conversationID, source: "diffable_apply")
    }

    func messageListDidApplySnapshot(conversationID: UUID, durationMs: Int, hasMorePending: Bool) {
        publishGate.isMessageListApplying = false
        DeepTutorChatLog.renderTransactionEnd(conversationID: conversationID, durationMs: durationMs)
        DeepTutorChatLog.refreshApplyCompleted(
            conversationID: conversationID,
            durationMs: durationMs,
            hasMorePending: hasMorePending
        )
        publishGate.flushAfterSnapshotApply()
    }
}

enum DeepTutorScrollPositionStore {
    private static let prefix = "deeptutor.scroll."

    static func save(anchorMessageID: UUID?, for conversationID: UUID) {
        UserDefaults.standard.set(anchorMessageID?.uuidString, forKey: prefix + conversationID.uuidString)
    }

    static func load(for conversationID: UUID) -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: prefix + conversationID.uuidString) else { return nil }
        return UUID(uuidString: raw)
    }
}

enum DeepTutorDraftStore {
    private static let prefix = "deeptutor.draft."

    static func loadDraft(for conversationID: UUID) -> String {
        UserDefaults.standard.string(forKey: prefix + conversationID.uuidString) ?? ""
    }

    static func saveDraft(_ text: String, for conversationID: UUID) {
        UserDefaults.standard.set(text, forKey: prefix + conversationID.uuidString)
    }
}
