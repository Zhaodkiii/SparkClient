import Combine
import Foundation

/// CHAT-000054：对话 Tab 分段：院内名医 / 普通对话。
enum ChatListSegment: String, CaseIterable, Hashable, Sendable {
    case hospitalAgents
    case conversations

    var localizedTitle: String {
        switch self {
        case .hospitalAgents:
            return L10n.text("chat.segment.hospital_agents", fallback: "院内名医")
        case .conversations:
            return L10n.text("chat.segment.conversations", fallback: "普通对话")
        }
    }
}

@MainActor
final class ChatListViewModel: ObservableObject {
    private let stateStore: ChatStateStore
    let sessionStore: AppSessionStore
    let memberContextStore: MemberContextStore
    private let loadMembersUseCase: LoadMembersUseCase
    private let selectMemberUseCase: SelectMemberUseCase
    private let selectedMemberIDPersistence: any SelectedMemberIDPersisting
    private let loadChatThreadsUseCase: LoadChatThreadsUseCase
    private let loadChatMessagesUseCase: LoadChatMessagesUseCase
    private let createThreadUseCase: CreateThreadUseCase
    private let deleteThreadUseCase: DeleteThreadUseCase
    private let updateThreadMetadataUseCase: UpdateChatThreadMetadataUseCase
    private let aiSettingsRepository: any AISettingsRepository
    private let chatSyncSupervisor: ChatSyncSupervisor
    private let notificationClient: any NotificationClient
    /// CHAT-000054：医院会话身份记忆；普通对话投影据此排除医院 Thread。
    private let hospitalScopeStore: HospitalConversationScopeStore?
    private let logger: Logger
    private var hasLoadedForList = false
    private var didAttemptEmptyListRemoteRefresh = false
    private var cancellables = Set<AnyCancellable>()

    /// CHAT-000054：对话 Tab 当前分段（院内名医 / 普通对话）。
    @Published var chatListSegment: ChatListSegment = .hospitalAgents
    /// CHAT-000054：医院 Demo 目录是否可用；不可用时隐藏分段选择器，只显示普通对话。
    @Published var hospitalCatalogAvailable: Bool = true

    /// 公共“获取可复用 Thread，必要时创建”编排器（CHAT-000041）。
    /// - Note: 单飞门在 account 级共享实例上保持，账号切换由 `resetForSessionSwitch()` 清空。
    private lazy var threadAcquisitionCoordinator: ChatThreadAcquisitionCoordinator = {
        ChatThreadAcquisitionCoordinator(
            stateStore: stateStore,
            createThread: { [weak self] memberID in
                guard let self else { return nil }
                if let memberID {
                    return await self.createThread(
                        memberID: memberID,
                        title: L10n.text("chat.default_thread_title")
                    )
                }
                return await self.createThread()
            },
            reloadThreads: { [weak self] in
                await self?.reloadThreads(selectFirstIfNeeded: false)
            },
            isAccountActive: { [weak self] accountID in
                guard let self else { return false }
                guard case .signedIn(let session) = self.sessionStore.state else { return false }
                return session.accountID == accountID
            },
            logger: logger
        )
    }()

    @Published private(set) var hasFinishedInitialLocalLoad = false
    @Published private(set) var isRefreshingEmptyListFallback = false
    @Published private(set) var isCreatingQuickStartThread = false
    @Published private(set) var quickStartCreationError: String?

    init(
        stateStore: ChatStateStore,
        sessionStore: AppSessionStore,
        memberContextStore: MemberContextStore,
        loadMembersUseCase: LoadMembersUseCase,
        selectMemberUseCase: SelectMemberUseCase,
        selectedMemberIDPersistence: any SelectedMemberIDPersisting,
        loadChatThreadsUseCase: LoadChatThreadsUseCase,
        loadChatMessagesUseCase: LoadChatMessagesUseCase,
        createThreadUseCase: CreateThreadUseCase,
        deleteThreadUseCase: DeleteThreadUseCase,
        updateThreadMetadataUseCase: UpdateChatThreadMetadataUseCase,
        aiSettingsRepository: any AISettingsRepository,
        chatSyncSupervisor: ChatSyncSupervisor,
        notificationClient: any NotificationClient,
        hospitalScopeStore: HospitalConversationScopeStore? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.stateStore = stateStore
        self.sessionStore = sessionStore
        self.memberContextStore = memberContextStore
        self.loadMembersUseCase = loadMembersUseCase
        self.selectMemberUseCase = selectMemberUseCase
        self.selectedMemberIDPersistence = selectedMemberIDPersistence
        self.loadChatThreadsUseCase = loadChatThreadsUseCase
        self.loadChatMessagesUseCase = loadChatMessagesUseCase
        self.createThreadUseCase = createThreadUseCase
        self.deleteThreadUseCase = deleteThreadUseCase
        self.updateThreadMetadataUseCase = updateThreadMetadataUseCase
        self.aiSettingsRepository = aiSettingsRepository
        self.chatSyncSupervisor = chatSyncSupervisor
        self.notificationClient = notificationClient
        self.hospitalScopeStore = hospitalScopeStore
        self.logger = logger

        NotificationCenter.default.publisher(for: .sparkChatDatabaseDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                Task { @MainActor in
                    guard case .signedIn = self.sessionStore.state else { return }
                    if let event = note.chatConversationChangeEvent {
                        guard event.affectsThreadList else { return }
                        if await self.tryPatchThreadList(for: event) {
                            return
                        }
                    }
                    await self.reloadThreads(selectFirstIfNeeded: false)
                }
            }
            .store(in: &cancellables)
    }

    func loadForListIfNeeded() async {
        guard hasLoadedForList == false else { return }
        hasLoadedForList = true
        await loadIfNeeded()
        hasFinishedInitialLocalLoad = true
        await refreshThreadsIfLocalEmpty(isSearching: false)
    }

    /// 本地列表首次加载完成且仍为空时，触发一次远端线程列表刷新（每页面生命周期最多一次）。
    func refreshThreadsIfLocalEmpty(isSearching: Bool) async {
        guard hasFinishedInitialLocalLoad else { return }
        guard isSearching == false else { return }
        guard didAttemptEmptyListRemoteRefresh == false else { return }
        guard isRefreshingEmptyListFallback == false else { return }
        guard stateStore.threadItems.isEmpty else { return }

        didAttemptEmptyListRemoteRefresh = true
        isRefreshingEmptyListFallback = true
        defer { isRefreshingEmptyListFallback = false }

        logger.info("会话列表本地为空，触发空结果兜底 refreshThreads", module: .general)
        await refreshThreads()
    }

    func loadIfNeeded() async {
        guard case .signedIn = sessionStore.state else { return }
        stateStore.setLoading(true)
        defer { stateStore.setLoading(false) }

        await ensureMemberContextLoaded()
        await reloadThreads(selectFirstIfNeeded: true)
    }

    func refreshThreads() async {
        do {
            try await chatSyncSupervisor.refreshThreadListIncremental()
        } catch {
            notificationClient.error(
                error.localizedDescription,
                title: L10n.text("common.error"),
                source: "chat.list.refresh"
            )
        }
        await reloadThreads(selectFirstIfNeeded: false)
    }

    /// CHAT-000029 3.1：默认绑定成员前置解析。
    /// 偏好读取失败或无选中成员时按未绑定创建，不阻塞新建。
    private func resolveInitialMemberIDForNewThread() async -> Int? {
        let snapshot = await aiSettingsRepository.loadSnapshot()
        guard snapshot.chatComposerStartupPreferences.memberProfileEnabled else { return nil }
        return memberContextStore.context.selectedMemberID
    }

    var signedInAccountID: Int64? {
        if case .signedIn(let session) = sessionStore.state {
            return session.accountID
        }
        return nil
    }

    /// CHAT-000030：返回新 threadID 供详情页内部切换使用；列表页入口可忽略返回值。
    @discardableResult
    func createThread() async -> UUID? {
        let title = L10n.text("chat.default_thread_title")
        let initialMemberID = await resolveInitialMemberIDForNewThread()
        return await createThread(memberID: initialMemberID, title: title)
    }

    /// 从医疗详情等外部上下文新建会话时使用显式成员，避免沿用首页当前成员。
    /// 新会话元数据由 ChatSyncSupervisor 后台同步，不阻塞进入会话。
    @discardableResult
    func createThread(memberID: Int?, title: String) async -> UUID {
        let thread = await createThreadUseCase.execute(
            memberID: memberID,
            title: title
        )
        await reloadThreads(selectFirstIfNeeded: false)
        stateStore.markThreadAsNewlyCreated(thread.id)
        stateStore.setSelectedThreadID(thread.id)
        return thread.id
    }

    /// 获取可复用 Thread（近期活跃或最近未开始会话），必要时创建（CHAT-000041）。
    /// - Parameters:
    ///   - memberID: nil 为全局范围（对话 Tab），非 nil 为严格同成员（医疗资料入口）。
    ///   - hasAvailableChatModel: 可用模型校验；仅在必须新建时调用。
    func acquireReusableThreadOrCreate(
        memberID: Int? = nil,
        hasAvailableChatModel: @escaping @MainActor () async -> Bool
    ) async -> ChatThreadAcquisitionResult {
        guard case .signedIn(let session) = sessionStore.state else {
            return .requiresAISettings
        }
        return await threadAcquisitionCoordinator.acquire(
            accountID: session.accountID,
            memberID: memberID,
            hasAvailableChatModel: hasAvailableChatModel
        )
    }

    @discardableResult
    func createQuickStartThread(
        mode: ChatQuickStartMode,
        source: String
    ) async -> UUID? {
        logger.info(
            "Chat 快捷建会话开始 mode=\(mode.rawValue) source=\(source)",
            module: .general
        )
        isCreatingQuickStartThread = true
        quickStartCreationError = nil
        defer { isCreatingQuickStartThread = false }

        let initialMemberID = await resolveInitialMemberIDForNewThread()
        let thread = await createThreadUseCase.execute(
            memberID: initialMemberID,
            title: mode.title
        )
        // 新会话元数据由 ChatSyncSupervisor 监听 threadsChanged 后台推送，不阻塞进入会话
        await reloadThreads(selectFirstIfNeeded: false)
        stateStore.markThreadAsNewlyCreated(thread.id)
        stateStore.setSelectedThreadID(thread.id)
        stateStore.setDraft(mode.initialDraft, for: thread.id)
        logger.info(
            "Chat 快捷建会话完成 thread=\(thread.id.uuidString.prefix(8)) source=\(source)",
            module: .general
        )
        return thread.id
    }

    func selectThread(_ threadID: UUID) {
        stateStore.setSelectedThreadID(threadID)
    }

    func selectAndPrepare(threadID: UUID) async {
        stateStore.setSelectedThreadID(threadID)
    }

    /// CHAT-000054：普通对话投影。所有可识别为医院会话的 Thread（本地 scope
    /// 或由服务端回源恢复的 scope）必须从普通列表与全局搜索中排除；
    /// 这些会话只能从院内名医目录或目录内“最近咨询”进入。
    var ordinaryThreadItems: [ChatThreadListItem] {
        guard let hospitalScopeStore, let accountID = signedInAccountID else {
            return stateStore.threadItems
        }
        return Self.excludingHospitalThreads(stateStore.threadItems) {
            hospitalScopeStore.scope(for: $0, accountID: accountID) != nil
        }
    }

    /// CHAT-000054：普通对话投影的纯过滤逻辑（独立出来便于单测）。
    static func excludingHospitalThreads(
        _ items: [ChatThreadListItem],
        isHospitalThread: (UUID) -> Bool
    ) -> [ChatThreadListItem] {
        items.filter { isHospitalThread($0.id) == false }
    }

    func search(text: String) -> [ChatThreadListItem] {
        let source = ordinaryThreadItems
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.isEmpty == false else { return source }
        return source.filter { item in
            item.thread.listDisplayTitle.lowercased().contains(query)
            || item.latestMessagePreview.lowercased().contains(query)
        }
    }

    func deleteThread(_ threadID: UUID) async {
        await deleteThreadUseCase.execute(threadID: threadID)
        await reloadThreads(selectFirstIfNeeded: true)
    }

    func updateThreadAppearance(
        threadID: UUID,
        title: String,
        iconName: String?,
        iconColorName: String?
    ) async {
        await updateThreadMetadataUseCase.updateAppearance(
            threadID: threadID,
            title: title,
            iconName: iconName,
            iconColorName: iconColorName
        )
        await reloadThreads(selectFirstIfNeeded: false)
    }

    func toggleThreadPinned(_ threadID: UUID) async {
        guard let item = stateStore.threadItems.first(where: { $0.id == threadID }) else { return }
        let now = Date()
        let isPinned = !item.thread.isPinned
        let pinnedAt: Date? = isPinned ? now : nil
        await updateThreadMetadataUseCase.updatePinState(
            threadID: threadID,
            isPinned: isPinned,
            pinnedAt: pinnedAt
        )
        await reloadThreads(selectFirstIfNeeded: false)
    }

    func resetForSessionSwitch() {
        hasLoadedForList = false
        hasFinishedInitialLocalLoad = false
        didAttemptEmptyListRemoteRefresh = false
        isRefreshingEmptyListFallback = false
        isCreatingQuickStartThread = false
        quickStartCreationError = nil
        threadAcquisitionCoordinator.reset()
    }

    private func reloadThreads(selectFirstIfNeeded: Bool) async {
        let threads = await loadChatThreadsUseCase.execute()
        stateStore.setThreads(threads)

        if selectFirstIfNeeded,
           stateStore.selectedThreadID == nil {
            stateStore.setSelectedThreadID(threads.first?.id)
        }
    }

    /// 已知 `threadID` 的变更：只刷新投影行，避免整表 `loadThreadListItems`。
    private func tryPatchThreadList(for event: ChatConversationChangeEvent) async -> Bool {
        guard let threadID = event.threadID else { return false }
        if stateStore.threadItems.isEmpty {
            return false
        }
        if let item = await loadChatThreadsUseCase.execute(threadID: threadID) {
            stateStore.upsertThreadListItem(item)
        } else {
            stateStore.removeThreadListItem(id: threadID)
        }
        return true
    }

    private func ensureMemberContextLoaded() async {
        if memberContextStore.context.members.isEmpty == false { return }
        guard case .signedIn(let session) = sessionStore.state else { return }
        let members = await loadMembersUseCase.execute()
        let persisted = selectedMemberIDPersistence.load(for: session.accountID)
        let preferred = memberContextStore.context.selectedMemberID ?? persisted
        let selectedID = selectMemberUseCase.execute(
            members: members,
            selectedID: preferred
        )
        memberContextStore.update(members: members, selectedMemberID: selectedID)
    }
}
