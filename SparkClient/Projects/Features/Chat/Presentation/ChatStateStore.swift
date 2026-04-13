import Combine
import Foundation

@MainActor
final class ChatStateStore: ObservableObject {
    private struct MessagePaging: Sendable {
        var hasMore: Bool
        var isLoadingMore: Bool
    }

    private struct StreamingAssistant: Sendable {
        let threadID: UUID
        let clientMessageID: UUID
        var state: ChatStreamingAssistantState
        let createdAt: Date
    }
    private let streamingReducer = ChatStreamingAssistantReducer()
    private let runtimeAttachmentBuilder = ChatToolRuntimeAttachmentBuilder()

    @Published private(set) var threadItems: [ChatThreadListItem] = []
    @Published private(set) var messagesByThread: [UUID: [ChatMessage]] = [:]
    @Published private(set) var selectedThreadID: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    @Published private var composerDrafts: [UUID: ChatComposerDraft] = [:]
    @Published private var streamingAssistants: [UUID: StreamingAssistant] = [:]
    @Published private var messagePagingByThread: [UUID: MessagePaging] = [:]
    /// Bumps on each streaming text/reasoning update so views can scroll even when message count is unchanged.
    @Published private(set) var streamingContentGeneration: UInt64 = 0

    var selectedThread: ChatThread? {
        threadItems.first(where: { $0.id == selectedThreadID })?.thread
    }

    var selectedMessages: [ChatMessage] {
        guard let selectedThreadID else { return [] }
        var messages = messagesByThread[selectedThreadID] ?? []
        if let streaming = streamingAssistants[selectedThreadID] {
            messages.append(
                ChatMessage(
                    id: streaming.clientMessageID,
                    threadID: streaming.threadID,
                    role: .assistant,
                    kind: streaming.state.kind,
                    content: streaming.state.content,
                    attachments: makeStreamingAttachments(from: streaming),
                    reasoningContent: streaming.state.reasoningContent,
                    reasoningDurationMs: streaming.state.reasoningDurationMs,
                    reasoningExpanded: true,
                    reasoningVisibility: .full,
                    clientMessageID: streaming.clientMessageID,
                    serverMessageID: nil,
                    deliveryState: .sending,
                    createdAt: streaming.createdAt,
                    serverUpdatedAt: nil,
                    isTombstone: false
                )
            )
        }
        return messages
    }

    func setThreads(_ items: [ChatThreadListItem]) {
        threadItems = items
        if let selectedThreadID, items.contains(where: { $0.id == selectedThreadID }) == false {
            self.selectedThreadID = items.first?.id
        }
        if self.selectedThreadID == nil {
            self.selectedThreadID = items.first?.id
        }
    }

    func setSelectedThreadID(_ threadID: UUID?) {
        selectedThreadID = threadID
    }

    /// - Parameter clearStreamingAssistant: Set `false` while a reply is streaming so mid-send reloads (e.g. after user message persist) do not wipe `streamingAssistants`.
    func setMessages(
        _ messages: [ChatMessage],
        for threadID: UUID,
        clearStreamingAssistant: Bool = true,
        hasMore: Bool? = nil
    ) {
        messagesByThread[threadID] = messages
        if clearStreamingAssistant {
            streamingAssistants[threadID] = nil
        }
        if let hasMore {
            let current = messagePagingByThread[threadID] ?? MessagePaging(hasMore: hasMore, isLoadingMore: false)
            messagePagingByThread[threadID] = MessagePaging(hasMore: hasMore, isLoadingMore: current.isLoadingMore)
        }
    }

    func prependMessages(_ messages: [ChatMessage], for threadID: UUID, hasMore: Bool) {
        guard messages.isEmpty == false else {
            let current = messagePagingByThread[threadID] ?? MessagePaging(hasMore: hasMore, isLoadingMore: false)
            messagePagingByThread[threadID] = MessagePaging(hasMore: hasMore, isLoadingMore: current.isLoadingMore)
            return
        }
        let current = messagesByThread[threadID] ?? []
        let existingIDs = Set(current.map(\.id))
        let mergedPrefix = messages.filter { existingIDs.contains($0.id) == false }
        messagesByThread[threadID] = mergedPrefix + current
        let paging = messagePagingByThread[threadID] ?? MessagePaging(hasMore: hasMore, isLoadingMore: false)
        messagePagingByThread[threadID] = MessagePaging(hasMore: hasMore, isLoadingMore: paging.isLoadingMore)
    }

    func setLoadingMore(_ loading: Bool, for threadID: UUID) {
        let current = messagePagingByThread[threadID] ?? MessagePaging(hasMore: true, isLoadingMore: false)
        messagePagingByThread[threadID] = MessagePaging(hasMore: current.hasMore, isLoadingMore: loading)
    }

    func hasMoreMessages(for threadID: UUID) -> Bool {
        messagePagingByThread[threadID]?.hasMore ?? false
    }

    func isLoadingMoreMessages(for threadID: UUID) -> Bool {
        messagePagingByThread[threadID]?.isLoadingMore ?? false
    }

    func setDraft(_ text: String, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.text = text
        }
    }

    func draft(for threadID: UUID?) -> String {
        composerDraft(for: threadID).text
    }

    func composerDraft(for threadID: UUID?) -> ChatComposerDraft {
        guard let threadID else { return ChatComposerDraft() }
        return composerDrafts[threadID] ?? ChatComposerDraft()
    }

    func clearDraft(for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.text = ""
            draft.attachments = []
            draft.isShowingAttachmentMenu = false
            draft.isShowingPhotoPicker = false
            draft.isShowingCamera = false
            draft.previewSelection = nil
        }
    }

    func clearComposer(for threadID: UUID?) {
        guard let threadID else { return }
        composerDrafts[threadID] = ChatComposerDraft()
    }

    func updateRuntimeFlags(
        for threadID: UUID?,
        update: (inout ChatComposerRuntimeFlags) -> Void
    ) {
        updateComposerDraft(for: threadID) { draft in
            update(&draft.runtimeFlags)
        }
    }

    func setSelectedChatModelName(_ name: String?, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.runtimeFlags.selectedChatModelName = name
        }
    }

    func setAttachmentMenuPresented(_ isPresented: Bool, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.isShowingAttachmentMenu = isPresented
        }
    }

    func setPhotoPickerPresented(_ isPresented: Bool, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.isShowingPhotoPicker = isPresented
        }
    }

    func setCameraPresented(_ isPresented: Bool, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.isShowingCamera = isPresented
        }
    }

    func appendComposerAttachments(_ attachments: [ChatComposerAttachmentPreview], for threadID: UUID?) {
        guard attachments.isEmpty == false else { return }
        updateComposerDraft(for: threadID) { draft in
            draft.attachments.append(contentsOf: attachments)
            draft.previewSelection = attachments.last?.id
        }
    }

    func removeComposerAttachment(id: UUID, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.attachments.removeAll { $0.id == id }
            if draft.previewSelection == id {
                draft.previewSelection = draft.attachments.last?.id
            }
        }
    }

    func setPreviewSelection(_ attachmentID: UUID?, for threadID: UUID?) {
        updateComposerDraft(for: threadID) { draft in
            draft.previewSelection = attachmentID
        }
    }

    func setLoading(_ value: Bool) {
        isLoading = value
    }

    func setSending(_ value: Bool) {
        isSending = value
    }

    func setError(_ message: String?) {
        errorMessage = message
    }

    func startStreamingAssistant(
        threadID: UUID,
        clientMessageID: UUID,
        kind: ChatMessageKind,
        createdAt: Date = Date()
    ) {
        streamingAssistants[threadID] = StreamingAssistant(
            threadID: threadID,
            clientMessageID: clientMessageID,
            state: .initial(kind: kind),
            createdAt: createdAt
        )
        streamingContentGeneration &+= 1
    }

    func updateStreamingAssistant(
        threadID: UUID,
        delta: ChatAssistantPartialDelta
    ) {
        guard var streaming = streamingAssistants[threadID] else { return }
        let changed = streamingReducer.reduce(
            state: &streaming.state,
            delta: delta
        )
        guard changed else { return }
        streamingAssistants[threadID] = streaming
        streamingContentGeneration &+= 1
    }

    func updateStreamingAssistant(
        threadID: UUID,
        kind: ChatMessageKind,
        content: String,
        reasoningContent: String?,
        toolName: String?,
        toolContent: String?
    ) {
        updateStreamingAssistant(
            threadID: threadID,
            delta: ChatAssistantPartialDelta(
                answer: content,
                reasoning: reasoningContent,
                kind: kind,
                toolName: toolName,
                toolContent: toolContent
            )
        )
    }

    func finishStreamingAssistant(threadID: UUID) {
        streamingAssistants[threadID] = nil
    }

    private func updateComposerDraft(
        for threadID: UUID?,
        update: (inout ChatComposerDraft) -> Void
    ) {
        guard let threadID else { return }
        var draft = composerDrafts[threadID] ?? ChatComposerDraft()
        update(&draft)
        composerDrafts[threadID] = draft
    }

    private func makeStreamingAttachments(from state: StreamingAssistant) -> [ChatAttachment] {
        runtimeAttachmentBuilder.build(
            toolName: state.state.toolName,
            toolContent: state.state.toolContent
        )
    }
}
