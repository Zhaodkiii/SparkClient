import Foundation

/// 统一封装任务执行记录的上报与本地缓存刷新。
@MainActor
final class TaskExecutionRecorder {
    private weak var taskManager: TaskManager?

    init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    func submit(
        task: HealthTask,
        status: TaskExecutionStatus,
        notes: String? = nil
    ) async throws {
        guard let taskManager else { return }
        let draft = TaskExecutionDraftBuilder.make(for: task, status: status, notes: notes)

        switch status {
        case .done:
            let payload = TaskExecutionPayload(
                executedAt: draft.makePayload().executedAt,
                value: draft.value,
                notes: draft.notes,
                businessType: draft.businessType,
                businessID: draft.businessID
            )
            try await taskManager.completeTask(taskID: task.id, payload: payload)
        case .skipped, .failed:
            try await taskManager.submitExecution(taskID: task.id, draft: draft)
        }
    }
}
