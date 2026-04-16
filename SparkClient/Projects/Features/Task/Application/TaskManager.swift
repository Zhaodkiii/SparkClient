import Foundation
import Combine

@MainActor
final class TaskManager: ObservableObject {
    static let shared = TaskManager()

    @Published private(set) var tasks: [HealthTask] = []
    @Published private(set) var lastSyncTime: Date?

    private var taskService: TaskService?
    private let notificationManager: TaskNotificationManager
    private var logger: Logger

    init(
        taskService: TaskService? = nil,
        notificationManager: TaskNotificationManager = .shared,
        logger: Logger = ConsoleLogger()
    ) {
        self.taskService = taskService
        self.notificationManager = notificationManager
        self.logger = logger
    }

    func configure(taskService: TaskService, logger: Logger = ConsoleLogger()) {
        self.taskService = taskService
        self.logger = logger
        self.lastSyncTime = taskService.lastSyncTime
    }

    func loadInitial(memberID: Int?) async {
        guard let taskService else {
            logger.warning("TaskManager 未配置 TaskService", module: .general)
            return
        }

        do {
            let tasks = try await taskService.fetchTasks(memberID: memberID, since: nil)

            self.tasks = tasks.sorted(by: sortTask)

            for task in tasks where task.status == .pending {
                await notificationManager.registerTaskNotification(for: task)
            }
            logger.info("任务初始加载完成 tasks=\(tasks.count)", module: .general)
        } catch {
            logger.error("任务初始加载失败: \(error.localizedDescription)", module: .general)
        }
    }

    func syncIncremental(memberID: Int?) async {
        guard let taskService else { return }

        do {
            let payload = try await taskService.sync(memberID: memberID, since: lastSyncTime ?? taskService.lastSyncTime)
            merge(tasks: payload.tasks)
            lastSyncTime = payload.serverTime

            // 同步后执行通知对齐：新增/更新任务重建提醒；完成/取消任务移除提醒。
            for task in payload.tasks {
                switch task.status {
                case .pending:
                    await notificationManager.updateTaskNotification(for: task)
                case .completed, .canceled:
                    await notificationManager.removeNotification(for: task)
                }
            }
        } catch {
            logger.error("任务增量同步失败: \(error.localizedDescription)", module: .general)
        }
    }

    func createTask(payload: TaskCreatePayload) async throws {
        guard let taskService else { return }
        let task = try await taskService.createTask(payload: payload)
        merge(tasks: [task])
        if task.status == .pending {
            await notificationManager.registerTaskNotification(for: task)
        }
    }

    func updateTask(taskID: Int, payload: TaskUpdatePayload) async throws {
        guard let taskService else { return }
        let task = try await taskService.updateTask(taskID: taskID, payload: payload)
        merge(tasks: [task])

        if task.status == .pending {
            await notificationManager.updateTaskNotification(for: task)
        } else {
            await notificationManager.removeNotification(for: task)
        }
    }

    func completeTask(taskID: Int) async throws {
        guard let taskService else { return }
        _ = try await taskService.completeTask(taskID: taskID)
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].status = .completed
            tasks[index].updatedAt = Date()
            await notificationManager.removeNotification(for: tasks[index])
        }
    }

    func cancelTask(taskID: Int) async throws {
        guard let taskService else { return }
        _ = try await taskService.cancelTask(taskID: taskID)
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].status = .canceled
            tasks[index].updatedAt = Date()
            await notificationManager.removeNotification(for: tasks[index])
        }
    }

    private func merge(tasks incoming: [HealthTask]) {
        guard incoming.isEmpty == false else { return }
        var map = Dictionary(uniqueKeysWithValues: self.tasks.map { ($0.id, $0) })
        for task in incoming {
            map[task.id] = task
        }
        self.tasks = Array(map.values).sorted(by: sortTask)
    }

    private func sortTask(_ lhs: HealthTask, _ rhs: HealthTask) -> Bool {
        let lhsDate = lhs.dueTime ?? lhs.startTime ?? lhs.updatedAt
        let rhsDate = rhs.dueTime ?? rhs.startTime ?? rhs.updatedAt
        if lhsDate == rhsDate {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhsDate < rhsDate
    }
}
