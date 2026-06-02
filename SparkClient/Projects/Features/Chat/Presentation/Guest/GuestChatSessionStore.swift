import Combine
import Foundation

@MainActor
final class GuestChatSessionStore: ObservableObject {
    @Published var config: GuestAIConfig?
    @Published var messages: [GuestChatMessage] = []

    func reset() {
        config = nil
        messages = []
    }

    func clearMessages() {
        messages = []
    }
}
