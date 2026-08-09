import Combine
import SwiftUI

/// 下拉刷新：用协议注入替代 async closure，避免 iOS 16 回部署时 View 字段元数据崩溃。
@MainActor
protocol ConversationMessageListRefreshHandling: AnyObject {
    func refreshMessageList() async
}

@MainActor
final class ConversationMessageListRefreshCoordinator: ObservableObject, ConversationMessageListRefreshHandling {
    let threadID: UUID
    private weak var detailViewModel: ChatDetailViewModel?
    @Published private(set) var layoutNonce: UInt64 = 0

    init(threadID: UUID, detailViewModel: ChatDetailViewModel) {
        self.threadID = threadID
        self.detailViewModel = detailViewModel
    }

    func refreshMessageList() async {
        await detailViewModel?.loadMessagesIfNeeded(for: threadID)
        layoutNonce += 1
    }
}

/// 会话消息列表 UI 命令（同步事件，避免 Representable 累积函数类型字段）。
enum ConversationListCommand: Equatable {
    case loadMore
    case captureOpenFiles
}

/// SwiftUI 桥接 UIKit 会话消息列表（增量 diff + 底部锚定）。
struct ConversationMessageListRepresentable: UIViewControllerRepresentable {
    let threadID: UUID
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var detailViewModel: ChatDetailViewModel
    @ObservedObject var uiStateStore: ChatMessageUIStateStore
    @ObservedObject var speechHelper: ChatSpeechHelper
    @ObservedObject var memberContextStore: MemberContextStore
    let taskManager: TaskManager
    let logger: Logger
    let actionStateHandle: ChatMessageActionStateHandle
    let conversationAppearance: ChatConversationAppearancePreferences

    var visibleMessages: [ChatMessage]
    var hasMoreMessages: Bool
    var isLoadingMoreMessages: Bool
    var lockBottomViewport: Bool
    var scrollToBottomRequestGeneration: UInt64

    let onCommand: (ConversationListCommand) -> Void
    let refreshHandler: any ConversationMessageListRefreshHandling
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
        vc.onCommand = onCommand
        vc.refreshHandler = refreshHandler
        return vc
    }

    func updateUIViewController(_ uiViewController: ConversationMessageListViewController, context: Context) {
        if context.coordinator.lastThreadID != threadID {
            context.coordinator.lastThreadID = threadID
            context.coordinator.appliedLayoutNonce = nil
            uiViewController.resetForNewThread()
        }
        wire(vc: uiViewController)
        uiViewController.onCommand = onCommand
        uiViewController.refreshHandler = refreshHandler
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
            lockBottomViewport: lockBottomViewport,
            scrollToBottomRequestGeneration: scrollToBottomRequestGeneration,
            forceFullListRediff: forceRediff
        )
        uiViewController.apply(threadID: threadID, payload: payload)
    }

    private func wire(vc: ConversationMessageListViewController) {
        vc.stateStore = stateStore
        vc.detailViewModel = detailViewModel
        vc.uiStateStore = uiStateStore
        vc.speechHelper = speechHelper
        vc.memberContextStore = memberContextStore
        vc.taskManager = taskManager
        vc.logger = logger
        vc.actionState = actionStateHandle.state
        vc.conversationAppearance = conversationAppearance
    }
}
