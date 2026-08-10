import Combine
import Foundation

@MainActor
final class ChatSwiftUIScrollAnchorPolicy: ObservableObject {
    @Published private(set) var hasUserInteractedSinceOpen = false

    private var lastScrollRequestGeneration: UInt64 = 0
    private var lastContentGeneration: UInt64 = 0

    func reset() {
        hasUserInteractedSinceOpen = false
        lastScrollRequestGeneration = 0
        lastContentGeneration = 0
    }

    func markUserInteraction() {
        hasUserInteractedSinceOpen = true
    }

    func shouldScrollToBottom(
        frame: ChatSwiftUIConversationFrame,
        behavior: ChatSwiftUIRefreshBehavior
    ) -> Bool {
        defer {
            lastScrollRequestGeneration = frame.scrollToBottomRequestGeneration
            lastContentGeneration = frame.generation
        }

        if frame.scrollToBottomRequestGeneration != lastScrollRequestGeneration {
            return true
        }

        if frame.lockBottomViewport && hasUserInteractedSinceOpen == false {
            return true
        }

        guard frame.generation != lastContentGeneration else { return false }

        switch behavior {
        case .stable:
            return hasUserInteractedSinceOpen == false
        case .followBottom:
            return true
        case .manualFirst:
            return false
        }
    }
}
