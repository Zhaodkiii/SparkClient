import Foundation

/// 从健康资源详情页启动 Chat 的公共编排器。
///
/// 详情页只发出 `HealthResourceConversationRequest`，不直接依赖 Chat UI、
/// API Key 设置页或 Thread Repository；所有跨模块副作用集中在这里完成。
@MainActor
final class HealthResourceConversationCoordinator {
    enum PreparationResult: Equatable {
        case ready(threadID: UUID)
        case requiresAISettings
        case failed(message: String)
    }

    private let stateStore: ChatStateStore
    private let listViewModel: ChatListViewModel
    private let detailViewModel: ChatDetailViewModel
    private let logger: Logger

    init(
        stateStore: ChatStateStore,
        listViewModel: ChatListViewModel,
        detailViewModel: ChatDetailViewModel,
        logger: Logger = ConsoleLogger()
    ) {
        self.stateStore = stateStore
        self.listViewModel = listViewModel
        self.detailViewModel = detailViewModel
        self.logger = logger
    }

    func prepare(_ request: HealthResourceConversationRequest) async -> PreparationResult {
        guard request.identity.resourceID > 0, request.identity.memberID > 0,
              request.identity.typedResource != nil else {
            return .failed(message: L10n.text(
                "chat.health_resource_conversation.invalid_resource",
                fallback: "当前健康资料暂时无法开启对话。"
            ))
        }

        guard await detailViewModel.hasAvailableChatModel() else {
            return .requiresAISettings
        }

        let title = L10n.text("chat.default_thread_title")
        let threadID = await listViewModel.createThread(
            memberID: request.identity.memberID,
            title: title
        )
        let ref = HealthResourceRef(
            identity: request.identity,
            displayTitle: request.displayTitle,
            displaySubtitle: request.displaySubtitle,
            typeBadge: request.typeBadge
        )
        stateStore.appendHealthResourceRefs([ref], for: threadID)

        guard let thread = stateStore.threadItems.first(where: { $0.id == threadID })?.thread,
              thread.memberID == request.identity.memberID,
              stateStore.composerDraft(for: threadID).pendingHealthResourceRefs.contains(where: { $0.id == ref.id }) else {
            logger.error(
                "健康资料快捷对话准备失败：Thread/Ref 成员或草稿不一致 thread=\(shortID(threadID)) member=\(request.identity.memberID)",
                module: .general
            )
            await listViewModel.deleteThread(threadID)
            return .failed(message: L10n.text(
                "chat.health_resource_conversation.prepare_failed",
                fallback: "对话准备失败，请稍后重试。"
            ))
        }

        logger.info(
            "健康资料快捷对话准备完成 source=\(request.source) type=\(request.identity.resourceType) resource=\(request.identity.resourceID) thread=\(shortID(threadID))",
            module: .general
        )
        return .ready(threadID: threadID)
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
