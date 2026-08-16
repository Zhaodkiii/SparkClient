import Combine
import Foundation

@MainActor
final class ChatSwiftUIScrollAnchorPolicy: ObservableObject {
    @Published private(set) var hasUserInteractedSinceOpen = false

    private var lastScrollRequestGeneration: UInt64 = 0
    private var lastContentGeneration: UInt64 = 0
    private var lastLayoutGeneration: UInt64 = 0
    private var hasScrolledToBottomSinceOpen = false

    func reset() {
        hasUserInteractedSinceOpen = false
        lastScrollRequestGeneration = 0
        lastContentGeneration = 0
        lastLayoutGeneration = 0
        hasScrolledToBottomSinceOpen = false
    }

    func markUserInteraction() {
        hasUserInteractedSinceOpen = true
    }

    func shouldScrollToBottom(
        frame: ChatSwiftUIConversationFrame,
        behavior: ChatSwiftUIRefreshBehavior,
        layoutGeneration: UInt64
    ) -> Bool {
        defer {
            lastScrollRequestGeneration = frame.scrollToBottomRequestGeneration
            lastContentGeneration = frame.generation
            lastLayoutGeneration = layoutGeneration
        }

        if frame.scrollToBottomRequestGeneration != lastScrollRequestGeneration {
            hasScrolledToBottomSinceOpen = true
            return true
        }

        if frame.lockBottomViewport && hasUserInteractedSinceOpen == false {
            hasScrolledToBottomSinceOpen = true
            return true
        }

        if layoutGeneration != lastLayoutGeneration,
           hasScrolledToBottomSinceOpen,
           hasUserInteractedSinceOpen == false {
            return true
        }

        guard frame.generation != lastContentGeneration else { return false }

        switch behavior {
        case .stable:
            let shouldScroll = hasUserInteractedSinceOpen == false
            hasScrolledToBottomSinceOpen = hasScrolledToBottomSinceOpen || shouldScroll
            return shouldScroll
        case .followBottom:
            hasScrolledToBottomSinceOpen = true
            return true
        case .manualFirst:
            return false
        }
    }
}
