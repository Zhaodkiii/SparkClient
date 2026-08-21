import SwiftUI

private struct ChatSwiftUIConversationInput: Equatable {
    let threadID: UUID
    let visibleMessages: [ChatMessage]
    let hasMoreMessages: Bool
    let isLoadingMoreMessages: Bool
    let lockBottomViewport: Bool
    let scrollToBottomRequestGeneration: UInt64
}

private struct ChatSwiftUIScrollEvent: Equatable {
    let generation: UInt64
    let scrollRequestGeneration: UInt64
    let layoutGeneration: UInt64
}

private struct ChatSwiftUIContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatSwiftUIConversationView: View {
    let threadID: UUID
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var detailViewModel: ChatDetailViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let knowledgeDependencies: KnowledgeFeatureDependencies
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @ObservedObject var uiStateStore: ChatMessageUIStateStore
    @ObservedObject var speechHelper: ChatSpeechHelper
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var navigationCoordinator: ChatMessageNavigationCoordinator
    let taskManager: TaskManager
    let logger: Logger
    let actionStateHandle: ChatMessageActionStateHandle
    let conversationAppearance: ChatConversationAppearancePreferences
    let uiPreferences: ChatConversationUIPreferences
    let visibleMessages: [ChatMessage]
    let hasMoreMessages: Bool
    let isLoadingMoreMessages: Bool
    let lockBottomViewport: Bool
    let scrollToBottomRequestGeneration: UInt64

    @StateObject private var refreshCoordinator: ConversationMessageListRefreshCoordinator
    @StateObject private var streamBuffer = ChatSwiftUIStreamEventBuffer()
    @StateObject private var frameScheduler = ChatSwiftUIFrameScheduler()
    @StateObject private var scrollPolicy = ChatSwiftUIScrollAnchorPolicy()
    @State private var layoutGeneration: UInt64 = 0
    @State private var measuredContentHeight: CGFloat = 0
    /// 当前 SwiftUI 列表已经完成首次初始化的 thread。
    /// SwiftUI 的 `onAppear` 不只代表首次进入会话（子页面 pop 返回也会触发），
    /// 用它区分「首次打开/切换会话」与「同 thread 导航返回」，后者不得重置滚动策略。
    @State private var initializedThreadID: UUID?

    init(
        threadID: UUID,
        stateStore: ChatStateStore,
        detailViewModel: ChatDetailViewModel,
        aiSettingsViewModel: AISettingsViewModel,
        knowledgeDependencies: KnowledgeFeatureDependencies,
        knowledgeViewModel: KnowledgeLibraryViewModel,
        uiStateStore: ChatMessageUIStateStore,
        speechHelper: ChatSpeechHelper,
        memberContextStore: MemberContextStore,
        navigationCoordinator: ChatMessageNavigationCoordinator,
        taskManager: TaskManager,
        logger: Logger,
        actionStateHandle: ChatMessageActionStateHandle,
        conversationAppearance: ChatConversationAppearancePreferences,
        uiPreferences: ChatConversationUIPreferences,
        visibleMessages: [ChatMessage],
        hasMoreMessages: Bool,
        isLoadingMoreMessages: Bool,
        lockBottomViewport: Bool,
        scrollToBottomRequestGeneration: UInt64
    ) {
        self.threadID = threadID
        self.stateStore = stateStore
        self.detailViewModel = detailViewModel
        self.aiSettingsViewModel = aiSettingsViewModel
        self.knowledgeDependencies = knowledgeDependencies
        self.knowledgeViewModel = knowledgeViewModel
        self.uiStateStore = uiStateStore
        self.speechHelper = speechHelper
        self.memberContextStore = memberContextStore
        self.navigationCoordinator = navigationCoordinator
        self.taskManager = taskManager
        self.logger = logger
        self.actionStateHandle = actionStateHandle
        self.conversationAppearance = conversationAppearance
        self.uiPreferences = uiPreferences
        self.visibleMessages = visibleMessages
        self.hasMoreMessages = hasMoreMessages
        self.isLoadingMoreMessages = isLoadingMoreMessages
        self.lockBottomViewport = lockBottomViewport
        self.scrollToBottomRequestGeneration = scrollToBottomRequestGeneration
        _refreshCoordinator = StateObject(
            wrappedValue: ConversationMessageListRefreshCoordinator(
                threadID: threadID,
                detailViewModel: detailViewModel
            )
        )
    }

    var body: some View {
        let input = ChatSwiftUIConversationInput(
            threadID: threadID,
            visibleMessages: visibleMessages,
            hasMoreMessages: hasMoreMessages,
            isLoadingMoreMessages: isLoadingMoreMessages,
            lockBottomViewport: lockBottomViewport,
            scrollToBottomRequestGeneration: scrollToBottomRequestGeneration
        )
        let frame = frameScheduler.frame
        let scrollEvent = ChatSwiftUIScrollEvent(
            generation: frame.generation,
            scrollRequestGeneration: frame.scrollToBottomRequestGeneration,
            layoutGeneration: layoutGeneration
        )

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: rowSpacing, pinnedViews: []) {
                    if frame.hasMoreMessages {
                        loadMoreRow
                    }

                    ForEach(frame.rows) { row in
                        ChatSwiftUIConversationMessageRow(
                            threadID: threadID,
                            row: row,
                            frame: frame,
                            stateStore: stateStore,
                            detailViewModel: detailViewModel,
                            aiSettingsViewModel: aiSettingsViewModel,
                            knowledgeDependencies: knowledgeDependencies,
                            knowledgeViewModel: knowledgeViewModel,
                            uiStateStore: uiStateStore,
                            speechHelper: speechHelper,
                            memberContextStore: memberContextStore,
                            navigationCoordinator: navigationCoordinator,
                            actionState: actionStateHandle.state,
                            conversationAppearance: conversationAppearance,
                            taskManager: taskManager,
                            logger: logger,
                            onHeightChangingUpdate: { update in
                                update()
                            }
                        )
                        .id(row.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(ChatSwiftUIConversationLayoutConstants.bottomAnchorID)
                }
                .padding(.vertical, verticalContentPadding)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ChatSwiftUIContentHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await refreshCoordinator.refreshMessageList()
                apply(input: input, reset: false)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in scrollPolicy.markUserInteraction() }
            )
            .onAppear {
                // 导航返回（同 thread pop 回来）不等于首次打开会话：
                // 只有尚未为当前 thread 完成初始化时才重置，避免返回后
                // 把历史 scrollToBottomRequestGeneration 当作新请求再次触底。
                let isThreadInitialAppearance = initializedThreadID != threadID
                apply(input: input, reset: isThreadInitialAppearance, openReason: .firstOpen)
                if isThreadInitialAppearance {
                    initializedThreadID = threadID
                }
            }
            .onChange(of: input) { _, newValue in
                apply(input: newValue, reset: false)
            }
            .onChange(of: threadID) { _, newThreadID in
                // 会话切换需要完整重置；这是 thread 边界而非导航返回，仍允许初始触底。
                apply(input: input, reset: true, openReason: .threadChanged)
                initializedThreadID = newThreadID
            }
            .onPreferenceChange(ChatSwiftUIContentHeightPreferenceKey.self) { height in
                guard abs(height - measuredContentHeight) > 0.5 else { return }
                measuredContentHeight = height
                layoutGeneration &+= 1
            }
            .task(id: scrollEvent) {
                await scrollIfNeeded(
                    proxy: proxy,
                    frame: frameScheduler.frame,
                    layoutGeneration: scrollEvent.layoutGeneration,
                    animated: false
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chatScrollDismissesKeyboardInteractively()
    }

    private var rowSpacing: CGFloat {
        switch conversationAppearance.cardStyle {
        case .standard:
            return 6
        case .bodyFocused:
            return 4
        }
    }

    private var verticalContentPadding: CGFloat {
        conversationAppearance.cardStyle == .bodyFocused ? 10 : 12
    }

    @ViewBuilder
    private var loadMoreRow: some View {
        if isLoadingMoreMessages {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在加载更早消息")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else {
            Button {
                Task { await detailViewModel.loadMoreMessages(for: threadID) }
            } label: {
                Text("加载更早消息")
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private func apply(
        input: ChatSwiftUIConversationInput,
        reset: Bool,
        openReason: ChatSwiftUIScrollOpenReason = .firstOpen
    ) {
        if reset {
            streamBuffer.reset()
            frameScheduler.reset()
        }

        let streamingStates = streamBuffer.ingest(messages: input.visibleMessages)
        let nextFrame = ChatSwiftUIConversationFrameBuilder.make(
            threadID: input.threadID,
            visibleMessages: input.visibleMessages,
            hasMoreMessages: input.hasMoreMessages,
            isLoadingMoreMessages: input.isLoadingMoreMessages,
            lockBottomViewport: input.lockBottomViewport,
            scrollToBottomRequestGeneration: input.scrollToBottomRequestGeneration,
            streamingStates: streamingStates
        )
        if reset {
            // 滚动策略必须以即将提交的 frame 为基线重置，否则历史
            // scrollToBottomRequestGeneration / 内容版本会被当作新变化重复消费。
            scrollPolicy.reset(
                to: nextFrame,
                layoutGeneration: layoutGeneration,
                reason: openReason
            )
        }
        let priority = reset
            ? ChatSwiftUIFramePriority.immediate
            : ChatSwiftUIConversationFrameBuilder.priority(
                previous: frameScheduler.frame,
                next: nextFrame
            )
        frameScheduler.submit(nextFrame, priority: priority)
    }

    @MainActor
    private func scrollIfNeeded(
        proxy: ScrollViewProxy,
        frame: ChatSwiftUIConversationFrame,
        layoutGeneration: UInt64,
        animated: Bool
    ) async {
        // The measured content height changes on every frame of a collapsing tool
        // trace. Since this task is keyed by `layoutGeneration`, it is cancelled
        // and restarted until the real layout has remained stable for two frames.
        try? await Task.sleep(for: .milliseconds(32))
        guard Task.isCancelled == false else { return }
        guard scrollPolicy.shouldScrollToBottom(
            frame: frame,
            behavior: uiPreferences.swiftUIRefreshBehavior,
            layoutGeneration: layoutGeneration
        ) else { return }

        let action = {
            proxy.scrollTo(ChatSwiftUIConversationLayoutConstants.bottomAnchorID, anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.18), action)
        } else {
            action()
        }
    }
}

private struct ChatSwiftUIConversationMessageRow: View {
    let threadID: UUID
    let row: ChatSwiftUIMessageRowModel
    let frame: ChatSwiftUIConversationFrame
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var detailViewModel: ChatDetailViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let knowledgeDependencies: KnowledgeFeatureDependencies
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @ObservedObject var uiStateStore: ChatMessageUIStateStore
    @ObservedObject var speechHelper: ChatSpeechHelper
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var navigationCoordinator: ChatMessageNavigationCoordinator
    let actionState: ChatMessageActionState
    let conversationAppearance: ChatConversationAppearancePreferences
    let taskManager: TaskManager
    let logger: Logger
    let onHeightChangingUpdate: (@escaping () -> Void) -> Void

    var body: some View {
        ChatConversationMessageRow(
            threadID: threadID,
            message: row.message,
            visibleMessages: frame.visibleMessages,
            stateStore: stateStore,
            detailViewModel: detailViewModel,
            aiSettingsViewModel: aiSettingsViewModel,
            knowledgeDependencies: knowledgeDependencies,
            knowledgeViewModel: knowledgeViewModel,
            uiStateStore: uiStateStore,
            speechHelper: speechHelper,
            memberContextStore: memberContextStore,
            navigationCoordinator: navigationCoordinator,
            actionState: actionState,
            conversationAppearance: conversationAppearance,
            taskManager: taskManager,
            logger: logger,
            onHeightChangingUpdate: onHeightChangingUpdate
        )
        .transaction { transaction in
            if row.streamingState.isStreaming {
                transaction.animation = nil
            }
        }
    }
}
