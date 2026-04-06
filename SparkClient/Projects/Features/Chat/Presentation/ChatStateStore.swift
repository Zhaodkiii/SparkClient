import Combine
import Foundation

@MainActor
final class ChatStateStore: ObservableObject {
    private struct StreamingAssistant: Sendable {
        let threadID: UUID
        let clientMessageID: UUID
        var kind: ChatMessageKind
        var content: String
        var reasoningContent: String?
        let createdAt: Date
    }

    @Published private(set) var threadItems: [ChatThreadListItem] = []
    @Published private(set) var messagesByThread: [UUID: [ChatMessage]] = [:]
    @Published private(set) var selectedThreadID: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    @Published private var composerDrafts: [UUID: ChatComposerDraft] = [:]
    @Published private var streamingAssistants: [UUID: StreamingAssistant] = [:]
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
                    kind: streaming.kind,
                    content: streaming.content,
                    attachments: [],
                    reasoningContent: streaming.reasoningContent,
                    reasoningDurationMs: nil,
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
    func setMessages(_ messages: [ChatMessage], for threadID: UUID, clearStreamingAssistant: Bool = true) {
        messagesByThread[threadID] = messages
        if clearStreamingAssistant {
            streamingAssistants[threadID] = nil
        }
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
            kind: kind,
            content: "",
            reasoningContent: nil,
            createdAt: createdAt
        )
        streamingContentGeneration &+= 1
    }

    func updateStreamingAssistant(
        threadID: UUID,
        kind: ChatMessageKind,
        content: String,
        reasoningContent: String?
    ) {
        guard var state = streamingAssistants[threadID] else { return }
        let reasoning = reasoningContent.flatMap { $0.isEmpty ? nil : $0 }
        guard state.content != content || state.kind != kind || state.reasoningContent != reasoning else { return }
        state.kind = kind
        state.content = content
        state.reasoningContent = reasoning
        streamingAssistants[threadID] = state
        streamingContentGeneration &+= 1
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
}
