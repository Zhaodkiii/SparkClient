import Combine
import Foundation

@MainActor
final class ChatStateStore: ObservableObject {
    @Published private(set) var threadItems: [ChatThreadListItem] = []
    @Published private(set) var messagesByThread: [UUID: [ChatMessage]] = [:]
    @Published private(set) var selectedThreadID: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    @Published private var drafts: [UUID: String] = [:]

    var selectedThread: ChatThread? {
        threadItems.first(where: { $0.id == selectedThreadID })?.thread
    }

    var selectedMessages: [ChatMessage] {
        guard let selectedThreadID else { return [] }
        return messagesByThread[selectedThreadID] ?? []
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
}
