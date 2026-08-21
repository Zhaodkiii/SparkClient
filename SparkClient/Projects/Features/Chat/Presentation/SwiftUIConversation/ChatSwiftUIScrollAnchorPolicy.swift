import Combine
import Foundation

/// 描述 SwiftUI 会话列表滚动策略重新初始化的原因。
/// `firstOpen` / `threadChanged` 允许等待一次初始触底；
/// `navigationReturn` 只对齐基线，不把历史状态当作新请求。
enum ChatSwiftUIScrollOpenReason: Equatable {
    case firstOpen
    case threadChanged
    case navigationReturn
}

@MainActor
final class ChatSwiftUIScrollAnchorPolicy: ObservableObject {
    @Published private(set) var hasUserInteractedSinceOpen = false

    private var lastScrollRequestGeneration: UInt64 = 0
    private var lastContentGeneration: UInt64 = 0
    private var lastLayoutGeneration: UInt64 = 0
    private var hasScrolledToBottomSinceOpen = false
    private var awaitsInitialBottomScroll = false

    /// 以 `frame` 作为基线重置滚动策略。
    ///
    /// 重置时必须以即将提交的 frame 对齐 `scrollToBottomRequestGeneration`、
    /// `generation` 与 `layoutGeneration`，否则导航返回等场景会把历史触底请求
    /// 或内容版本当作新变化重复消费（返回会话误触底部滚动的根因）。
    /// 初始触底由 open reason 显式表达，不再依赖 generation 差异。
    func reset(
        to frame: ChatSwiftUIConversationFrame,
        layoutGeneration: UInt64,
        reason: ChatSwiftUIScrollOpenReason
    ) {
        hasUserInteractedSinceOpen = false
        hasScrolledToBottomSinceOpen = false
        lastScrollRequestGeneration = frame.scrollToBottomRequestGeneration
        lastContentGeneration = frame.generation
        lastLayoutGeneration = layoutGeneration
        awaitsInitialBottomScroll = reason != .navigationReturn
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
            awaitsInitialBottomScroll = false
            hasScrolledToBottomSinceOpen = true
            return true
        }

        if awaitsInitialBottomScroll {
            // 用户在初始触底前已经交互，放弃初始触底，避免抢占滚动位置。
            if hasUserInteractedSinceOpen {
                awaitsInitialBottomScroll = false
                return false
            }
            // 首帧可能还没有消息数据，等 rows 就绪后再触底。
            guard frame.rows.isEmpty == false else { return false }
            awaitsInitialBottomScroll = false
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
