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

        // 先确保本地 Thread 列表可用于选择。复用既有会话不要求当前模型可用；
        // 用户仍可查看历史和已带入的预览，发送时沿用 Chat 自身的模型门控。
        await listViewModel.loadForListIfNeeded()

        let ref = HealthResourceRef(
            identity: request.identity,
            displayTitle: request.displayTitle,
            displaySubtitle: request.displaySubtitle,
            typeBadge: request.typeBadge
        )

        // CHAT-000041：与对话 Tab 共用同一套“复用/创建”决策与单飞门，
        // 保持严格同成员候选范围，避免两处规则漂移。
        let acquisition = await listViewModel.acquireReusableThreadOrCreate(
            memberID: request.identity.memberID,
            hasAvailableChatModel: { [weak detailViewModel] in
                await detailViewModel?.hasAvailableChatModel() ?? false
            }
        )
        switch acquisition {
        case .reuse(let threadID, _):
            return await prepareReference(
                ref,
                request: request,
                threadID: threadID,
                createdByThisRequest: false
            )
        case .created(let threadID):
            return await prepareReference(
                ref,
                request: request,
                threadID: threadID,
                createdByThisRequest: true
            )
        case .requiresAISettings:
            return .requiresAISettings
        }
    }

    private func prepareReference(
        _ ref: HealthResourceRef,
        request: HealthResourceConversationRequest,
        threadID: UUID,
        createdByThisRequest: Bool
    ) async -> PreparationResult {
        guard let thread = stateStore.threadItems.first(where: { $0.id == threadID })?.thread,
              thread.memberID == request.identity.memberID else {
            return await failReferencePreparation(
                request: request,
                threadID: threadID,
                createdByThisRequest: createdByThisRequest,
                messageKey: "chat.health_resource_conversation.prepare_failed",
                fallback: "对话准备失败，请稍后重试。"
            )
        }

        let before = stateStore.composerDraft(for: threadID).pendingHealthResourceRefs
        if before.contains(where: { $0.id == ref.id }) {
            logger.info(
                "健康资料快捷对话复用已有引用 decision=reuse source=\(request.source) type=\(request.identity.resourceType) resource=\(request.identity.resourceID) thread=\(shortID(threadID))",
                module: .general
            )
            return .ready(threadID: threadID)
        }

        guard before.count < HealthResourceSendValidator.maxRefs else {
            return await failReferencePreparation(
                request: request,
                threadID: threadID,
                createdByThisRequest: createdByThisRequest,
                messageKey: "chat.ask_report.toast.max_refs",
                fallback: "当前对话最多关联 5 份健康资料，请先移除部分资料。"
            )
        }

        stateStore.appendHealthResourceRefs([ref], for: threadID)
        let after = stateStore.composerDraft(for: threadID).pendingHealthResourceRefs
        guard after.contains(where: { $0.id == ref.id }) else {
            return await failReferencePreparation(
                request: request,
                threadID: threadID,
                createdByThisRequest: createdByThisRequest,
                messageKey: "chat.health_resource_conversation.prepare_failed",
                fallback: "对话准备失败，请稍后重试。",
                rollbackRef: ref
            )
        }

        logger.info(
            "健康资料快捷对话准备完成 decision=\(createdByThisRequest ? "create" : "reuse") source=\(request.source) type=\(request.identity.resourceType) resource=\(request.identity.resourceID) thread=\(shortID(threadID))",
            module: .general
        )
        return .ready(threadID: threadID)
    }

    private func failReferencePreparation(
        request: HealthResourceConversationRequest,
        threadID: UUID,
        createdByThisRequest: Bool,
        messageKey: String,
        fallback: String,
        rollbackRef: HealthResourceRef? = nil
    ) async -> PreparationResult {
        if let rollbackRef {
            stateStore.removeHealthResourceRef(rollbackRef, for: threadID)
        }
        logger.error(
            "健康资料快捷对话准备失败 decision=\(createdByThisRequest ? "create" : "reuse") source=\(request.source) type=\(request.identity.resourceType) resource=\(request.identity.resourceID) thread=\(shortID(threadID)) member=\(request.identity.memberID)",
            module: .general
        )
        if createdByThisRequest {
            await listViewModel.deleteThread(threadID)
        }
        return .failed(message: L10n.text(messageKey, fallback: fallback))
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
