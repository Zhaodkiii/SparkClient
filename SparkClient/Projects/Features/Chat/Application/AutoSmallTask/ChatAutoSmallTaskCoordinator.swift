import Foundation

@MainActor
final class ChatAutoSmallTaskCoordinator {
    private let intentStore: ChatAutoSmallTaskIntentStore
    private let aiConfigCenter: AIConfigCenter
    private let notificationClient: any NotificationClient
    private let logger: Logger
    private var runningThreadIDs: Set<UUID> = []

    init(
        intentStore: ChatAutoSmallTaskIntentStore,
        aiConfigCenter: AIConfigCenter,
        notificationClient: any NotificationClient,
        logger: Logger = ConsoleLogger()
    ) {
        self.intentStore = intentStore
        self.aiConfigCenter = aiConfigCenter
        self.notificationClient = notificationClient
        self.logger = logger
    }

    func trySendIfNeeded(
        threadID: UUID,
        selectedModelRow: AIScenarioRemoteModelRow?,
        stateStore: ChatStateStore,
        detailViewModel: ChatDetailViewModel
    ) async {
        guard runningThreadIDs.contains(threadID) == false else { return }
        guard let intent = intentStore.pendingIntent(for: threadID) else { return }
        guard intentStore.markRunning(intent) else { return }
        runningThreadIDs.insert(threadID)
        defer { runningThreadIDs.remove(threadID) }

        guard stateStore.selectedThreadID == threadID else {
            intentStore.markFailed(threadID: threadID)
            return
        }
        guard stateStore.isSending == false else {
            intentStore.markFailed(threadID: threadID)
            return
        }

        guard draftHasNotChanged(threadID: threadID, intent: intent, stateStore: stateStore) else {
            logger.info(
                "auto_small_task.send.cancelled draft_changed thread=\(threadID.uuidString.prefix(8)) businessKey=\(intent.businessKey.rawValue)",
                module: .general
            )
            intentStore.markFailed(threadID: threadID)
            return
        }

        guard let task = await resolveTask(intent: intent, ownerAccountID: nil) else {
            intentStore.markFailed(threadID: threadID)
            notificationClient.error(
                L10n.text("chat.auto_small_task.init_failed", fallback: "体检计划小任务初始化失败，请稍后重试。"),
                title: nil,
                source: "chat.auto_small_task"
            )
            return
        }

        guard let selectedModelRow else {
            intentStore.markFailed(threadID: threadID)
            notificationClient.error(
                L10n.text("chat.auto_small_task.model_unavailable", fallback: "当前模型暂不支持体检计划小任务，请切换模型后重试。"),
                title: nil,
                source: "chat.auto_small_task"
            )
            return
        }

        guard modelSupports(task: task, row: selectedModelRow) else {
            intentStore.markFailed(threadID: threadID)
            notificationClient.error(
                L10n.text("chat.auto_small_task.model_unavailable", fallback: "当前模型暂不支持体检计划小任务，请切换模型后重试。"),
                title: nil,
                source: "chat.auto_small_task"
            )
            return
        }

        logger.info(
            "auto_small_task.send.start thread=\(threadID.uuidString.prefix(8)) businessKey=\(intent.businessKey.rawValue) code=\(intent.smallTaskCode)",
            module: .general
        )

        do {
            try await Task.sleep(nanoseconds: 500_000_000)
        } catch {
            intentStore.markFailed(threadID: threadID)
            return
        }

        guard stateStore.selectedThreadID == threadID, stateStore.isSending == false else {
            intentStore.markFailed(threadID: threadID)
            return
        }

        if draftHasNotChanged(threadID: threadID, intent: intent, stateStore: stateStore) {
            stateStore.clearDraft(for: threadID)
        }
        detailViewModel.startSmallTask(task)
        intentStore.markConsumed(threadID: threadID)
        logger.info(
            "auto_small_task.send.success thread=\(threadID.uuidString.prefix(8)) businessKey=\(intent.businessKey.rawValue)",
            module: .general
        )
    }

    private func resolveTask(intent: ChatAutoSmallTaskIntent, ownerAccountID: Int64?) async -> SmallTask? {
        let normalizedCode = normalize(intent.smallTaskCode)
        let tasks = await aiConfigCenter.effectiveSmallTasks()
        if let task = tasks.first(where: { normalize($0.code) == normalizedCode }) {
            return task
        }
        await aiConfigCenter.reloadLocalSnapshot(ownerAccountID: ownerAccountID)
        return await aiConfigCenter.effectiveSmallTasks()
            .first { normalize($0.code) == normalizedCode }
    }

    private func modelSupports(task: SmallTask, row: AIScenarioRemoteModelRow) -> Bool {
        guard task.toolList.isEmpty == false else { return true }
        guard row.supportsToolUse else { return false }
        let modelTools = Set(row.aiToolScenarios.map(normalize))
        guard modelTools.isEmpty == false else { return true }
        let taskTools = Set(task.toolList.map(normalize))
        return taskTools.intersection(modelTools).isEmpty == false
    }

    private func draftHasNotChanged(
        threadID: UUID,
        intent: ChatAutoSmallTaskIntent,
        stateStore: ChatStateStore
    ) -> Bool {
        guard let initialDraftHash = intent.initialDraftHash else { return true }
        return ChatAutoSmallTaskDraftHasher.hash(stateStore.draft(for: threadID)) == initialDraftHash
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

