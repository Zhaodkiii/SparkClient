import Combine
import Foundation

@MainActor
final class ChatStateStore: ObservableObject {
    private struct StreamingAssistant: Sendable {
        let threadID: UUID
        let clientMessageID: UUID
        var kind: ChatMessageKind
        var content: String
        let createdAt: Date
    }

    @Published private(set) var threadItems: [ChatThreadListItem] = []
    @Published private(set) var messagesByThread: [UUID: [ChatMessage]] = [:]
    @Published private(set) var selectedThreadID: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    @Published private var drafts: [UUID: String] = [:]
    @Published private var streamingAssistants: [UUID: StreamingAssistant] = [:]

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

    func setMessages(_ messages: [ChatMessage], for threadID: UUID) {
        messagesByThread[threadID] = messages
        streamingAssistants[threadID] = nil
    }

    func setDraft(_ text: String, for threadID: UUID?) {
        guard let threadID else { return }
        drafts[threadID] = text
    }

    func draft(for threadID: UUID?) -> String {
        guard let threadID else { return "" }
        return drafts[threadID] ?? ""
    }

    func clearDraft(for threadID: UUID?) {
        guard let threadID else { return }
        drafts[threadID] = ""
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
            createdAt: createdAt
        )
    }

    func updateStreamingAssistant(
        threadID: UUID,
        kind: ChatMessageKind,
        content: String
    ) {
        guard var state = streamingAssistants[threadID] else { return }
        guard state.content != content || state.kind != kind else { return }
        state.kind = kind
        state.content = content
        streamingAssistants[threadID] = state
    }

    func finishStreamingAssistant(threadID: UUID) {
        streamingAssistants[threadID] = nil
    }
}
