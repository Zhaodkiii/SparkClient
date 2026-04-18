import SwiftUI

/// SwiftUI 桥接 UIKit 会话消息列表（增量 diff + 底部锚定）。
struct ConversationMessageListRepresentable: UIViewControllerRepresentable {
    let threadID: UUID
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var detailViewModel: ChatDetailViewModel
    @ObservedObject var uiStateStore: ChatMessageUIStateStore
    @ObservedObject var speechHelper: ChatSpeechHelper
    let taskManager: TaskManager
    let logger: Logger
    let actionState: ChatMessageActionState

    var visibleMessages: [ChatMessage]
    var hasMoreMessages: Bool
    var isLoadingMoreMessages: Bool
    var streamingContentGeneration: UInt64

    var onLoadMore: () -> Void
    var onRefresh: () async -> Void
    /// 递增时下一帧列表按 ``ConversationListApplyPayload/forceFullListRediff`` 全量重 diff（如下拉刷新）。
    var conversationListLayoutNonce: UInt64

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastThreadID: UUID?
        /// `nil` 表示尚未应用过当前线程的第一帧，避免把「首帧」误判为强制全量重 diff。
        var appliedLayoutNonce: UInt64?
    }

    func makeUIViewController(context: Context) -> ConversationMessageListViewController {
        let vc = ConversationMessageListViewController()
        context.coordinator.lastThreadID = threadID
        wire(vc: vc)
        vc.onLoadMore = onLoadMore
        vc.onRefresh = onRefresh
        return vc
    }

    func updateUIViewController(_ uiViewController: ConversationMessageListViewController, context: Context) {
        if context.coordinator.lastThreadID != threadID {
            context.coordinator.lastThreadID = threadID
            context.coordinator.appliedLayoutNonce = nil
            uiViewController.resetForNewThread()
        }
        wire(vc: uiViewController)
        let forceRediff: Bool = {
            if let prev = context.coordinator.appliedLayoutNonce {
                return prev != conversationListLayoutNonce
            }
            return false
        }()
        context.coordinator.appliedLayoutNonce = conversationListLayoutNonce
        let payload = ConversationListApplyPayload(
            messages: visibleMessages,
            hasMoreMessages: hasMoreMessages,
            isLoadingMoreMessages: isLoadingMoreMessages,
            streamingContentGeneration: streamingContentGeneration,
            forceFullListRediff: forceRediff
        )
        uiViewController.apply(threadID: threadID, payload: payload)
    }

    private func wire(vc: ConversationMessageListViewController) {
        vc.stateStore = stateStore
        vc.detailViewModel = detailViewModel
        vc.uiStateStore = uiStateStore
        vc.speechHelper = speechHelper
        vc.taskManager = taskManager
        vc.logger = logger
        vc.actionState = actionState
    }
}
