import Combine
import Foundation

@MainActor
final class GuestChatViewModel: ObservableObject {
    @Published private(set) var isSending = false
    @Published var errorMessage: String?

    let sessionStore: GuestChatSessionStore
    private let aiClient: GuestAIChatClient

    init(
        sessionStore: GuestChatSessionStore,
        aiClient: GuestAIChatClient
    ) {
        self.sessionStore = sessionStore
        self.aiClient = aiClient
    }

    var config: GuestAIConfig? { sessionStore.config }
    var messages: [GuestChatMessage] { sessionStore.messages }
    var hasConfig: Bool { sessionStore.config != nil }

    func applyConfig(_ config: GuestAIConfig) {
        sessionStore.config = config
        sessionStore.clearMessages()
        appendWelcomeMessageIfNeeded()
    }

    func appendWelcomeMessageIfNeeded() {
        guard sessionStore.messages.isEmpty else { return }
        sessionStore.messages.append(
            GuestChatMessage(
                role: .assistant,
                text: L10n.text("guest.chat.welcome")
            )
        )
    }

    func clearMessages() {
        sessionStore.clearMessages()
        appendWelcomeMessageIfNeeded()
    }

    func exitGuestMode() {
        sessionStore.reset()
    }

    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard let config = sessionStore.config else { return }
        guard isSending == false else { return }

        errorMessage = nil
        isSending = true

        let userMessage = GuestChatMessage(role: .user, text: trimmed)
        sessionStore.messages.append(userMessage)

        do {
            let reply = try await aiClient.send(messages: sessionStore.messages, config: config)
            sessionStore.messages.append(GuestChatMessage(role: .assistant, text: reply))
        } catch {
            errorMessage = error.localizedDescription
            sessionStore.messages.append(
                GuestChatMessage(
                    role: .assistant,
                    text: L10n.format("guest.chat.error_prefix", error.localizedDescription)
                )
            )
        }

        isSending = false
    }
}
