import Foundation
import Combine
import UIKit

@MainActor
final class TaskManager: ObservableObject {
    static let shared = TaskManager()

    @Published private(set) var tasks: [HealthTask] = []
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var lastSyncError: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var executions: [TaskExecutionRecord] = []
    @Published private(set) var isSubmittingExecution = false

    let statisticsStore = TaskStatisticsStore()
    lazy var executionRecorder: TaskExecutionRecorder = TaskExecutionRecorder(taskManager: self)

    private var taskService: TaskService?
    private let notificationManager: TaskNotificationManager
    private var logger: Logger
    private var executionsByTaskID: [Int: [TaskExecutionRecord]] = [:]
    private var accountID: Int64?
    private var cancellables: Set<AnyCancellable> = []

    init(
        taskService: TaskService? = nil,
        notificationManager: TaskNotificationManager = .shared,
        logger: Logger = ConsoleLogger()
    ) {
        self.taskService = taskService
        self.notificationManager = notificationManager
        self.logger = logger
        Publishers.Merge(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification),
            NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)
        )
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.notificationManager.reconcile(tasks: self.tasks)
            }
        }
        .store(in: &cancellables)
    }

    func configure(taskService: TaskService, logger: Logger = ConsoleLogger()) {
        self.taskService = taskService
        self.logger = logger
        self.lastSyncTime = taskService.lastSyncTime
    }

    func configureAccount(_ accountID: Int64) {
        guard self.accountID != accountID else { return }
        self.accountID = accountID
        notificationManager.configure(accountID: accountID)
    }

    func clearAccount() async {
        await notificationManager.clearCurrentAccount()
        accountID = nil
        tasks = []
        lastSyncTime = nil
        lastSyncError = nil
    }

    func task(for id: Int) -> HealthTask? {
        tasks.first { $0.id == id }
    }

    func executions(for taskID: Int) -> [TaskExecutionRecord] {
        executionsByTaskID[taskID] ?? []
    }

    func visibleTasks(filters: TaskFilterSelection, memberID: Int?) -> [HealthTask] {
        let scoped = scopedTasks(memberID: memberID)
        return TaskSorters.makeVisibleTasks(tasks: scoped, filters: filters)
    }

    func listOverview(memberID: Int?) -> TaskListOverview {
        TaskListOverview.build(from: scopedTasks(memberID: memberID))
    }

    func loadInitial(memberID: Int?) async {
        guard let taskService else {
            logger.warning("TaskManager 未配置 TaskService", module: .general)
            return
        }

        do {
            let tasks = try await taskService.fetchTasks(memberID: memberID, since: nil)
            self.tasks = tasks.sorted { TaskSorters.compare($0, $1, now: Date()) }

            await notificationManager.reconcile(tasks: tasks)
            refreshStatisticsStore(memberID: memberID)
            logger.info("任务初始加载完成 tasks=\(tasks.count)", module: .general)
        } catch {
            logger.error("任务初始加载失败: \(error.localizedDescription)", module: .general)
        }
    }

    func syncIncremental(memberID: Int?) async {
        guard let taskService else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let payload = try await taskService.sync(memberID: memberID, since: lastSyncTime ?? taskService.lastSyncTime)
            merge(tasks: payload.tasks)
            lastSyncTime = payload.serverTime
            lastSyncError = nil

            await notificationManager.reconcile(tasks: tasks)
            refreshStatisticsStore(memberID: memberID)
        } catch {
            lastSyncError = error.localizedDescription
            logger.error("任务增量同步失败: \(error.localizedDescription)", module: .general)
        }
    }

    func loadExecutions(taskID: Int) async {
        guard let taskService else { return }
        do {
            let records = try await taskService.fetchExecutions(taskID: taskID)
            executionsByTaskID[taskID] = records
            mergeExecutionRecords(records)
        } catch {
            logger.error("加载执行记录失败 task_id=\(taskID): \(error.localizedDescription)", module: .general)
        }
    }

    @discardableResult
    func createTaskReturningTask(payload: TaskCreatePayload) async throws -> HealthTask {
        guard let taskService else {
            throw TaskManagerError.taskServiceNotConfigured
        }
        let task = try await taskService.createTask(payload: payload)
        merge(tasks: [task])
        await notificationManager.reconcile(tasks: tasks, requestPermissionIfNeeded: true)
        refreshStatisticsStore(memberID: task.member)
        return task
    }

    func createTask(payload: TaskCreatePayload) async throws {
        _ = try await createTaskReturningTask(payload: payload)
    }

    func updateTask(taskID: Int, payload: TaskUpdatePayload, scope: TaskRepeatEditScope = .instance) async throws {
        guard let taskService else { return }
        var finalPayload = payload
        if scope == .plan, payload.repeatType == nil {
            finalPayload = TaskUpdatePayload(
                title: payload.title,
                description: payload.description,
                status: payload.status,
                startTime: payload.startTime,
                dueTime: payload.dueTime,
                repeatType: tasks.first(where: { $0.id == taskID })?.repeatType,
                priority: payload.priority,
                extra: payload.extra,
                notificationEnabled: payload.notificationEnabled,
                taskMedical: payload.taskMedical,
                taskExercise: payload.taskExercise,
                taskDiet: payload.taskDiet
            )
        }
        let task = try await taskService.updateTask(taskID: taskID, payload: finalPayload)
        merge(tasks: [task])

        await notificationManager.reconcile(tasks: tasks)
        refreshStatisticsStore(memberID: task.member)
    }

    @discardableResult
    func setNotificationEnabled(taskID: Int, enabled: Bool) async throws -> TaskNotificationSchedulingState {
        guard let taskService, let current = task(for: taskID) else {
            throw TaskManagerError.taskServiceNotConfigured
        }

        if enabled == false {
            await notificationManager.removeNotification(for: current)
        }

        do {
            let payload = TaskUpdatePayload(
                title: nil, description: nil, status: nil, startTime: nil, dueTime: nil,
                repeatType: nil, priority: nil, extra: nil, notificationEnabled: enabled,
                taskMedical: nil, taskExercise: nil, taskDiet: nil
            )
            let updated = try await taskService.updateTask(taskID: taskID, payload: payload)
            merge(tasks: [updated])
            await notificationManager.reconcile(tasks: tasks, requestPermissionIfNeeded: enabled)
            return await notificationManager.schedulingState(for: updated)
        } catch {
            if current.notificationEnabled {
                await notificationManager.reconcile(tasks: tasks)
            }
            throw error
        }
    }

    func notificationSchedulingState(for task: HealthTask) async -> TaskNotificationSchedulingState {
        await notificationManager.schedulingState(for: task)
    }

    func completeTask(taskID: Int, payload: TaskExecutionPayload? = nil) async throws {
        guard let taskService else { return }
        _ = try await taskService.completeTask(taskID: taskID, payload: payload)
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].status = .completed
            tasks[index].updatedAt = Date()
            await notificationManager.removeNotification(for: tasks[index])
            await notificationManager.reconcile(tasks: tasks)
            refreshStatisticsStore(memberID: tasks[index].member)
        }
        await loadExecutions(taskID: taskID)
    }

    func submitExecution(taskID: Int, draft: TaskExecutionDraft) async throws {
        guard let taskService else { return }
        isSubmittingExecution = true
        defer { isSubmittingExecution = false }

        let record = try await taskService.submitExecution(taskID: taskID, payload: draft.makePayload())
        mergeExecutionRecords([record])

        if draft.status == .done, let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].status = .completed
            tasks[index].updatedAt = Date()
            await notificationManager.removeNotification(for: tasks[index])
            await notificationManager.reconcile(tasks: tasks)
        }
        refreshStatisticsStore(memberID: tasks.first(where: { $0.id == taskID })?.member)
    }

    func cancelTask(taskID: Int) async throws {
        guard let taskService else { return }
        _ = try await taskService.cancelTask(taskID: taskID)
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].status = .canceled
            tasks[index].updatedAt = Date()
            await notificationManager.removeNotification(for: tasks[index])
            await notificationManager.reconcile(tasks: tasks)
            refreshStatisticsStore(memberID: tasks[index].member)
        }
    }

    private func scopedTasks(memberID: Int?) -> [HealthTask] {
        guard let memberID else { return tasks }
        return tasks.filter { $0.member == memberID }
    }

    private func merge(tasks incoming: [HealthTask]) {
        guard incoming.isEmpty == false else { return }
        var map = Dictionary(uniqueKeysWithValues: self.tasks.map { ($0.id, $0) })
        for task in incoming {
            map[task.id] = task
        }
        self.tasks = Array(map.values).sorted { TaskSorters.compare($0, $1, now: Date()) }
    }

    private func mergeExecutionRecords(_ incoming: [TaskExecutionRecord]) {
        guard incoming.isEmpty == false else { return }
        var map = Dictionary(uniqueKeysWithValues: executions.map { ($0.id, $0) })
        for record in incoming {
            map[record.id] = record
            var taskRecords = executionsByTaskID[record.task] ?? []
            if let index = taskRecords.firstIndex(where: { $0.id == record.id }) {
                taskRecords[index] = record
            } else {
                taskRecords.append(record)
            }
            executionsByTaskID[record.task] = taskRecords.sorted { $0.executedAt > $1.executedAt }
        }
        executions = Array(map.values).sorted { $0.executedAt > $1.executedAt }
    }

    private func refreshStatisticsStore(memberID: Int?) {
        statisticsStore.update(
            tasks: scopedTasks(memberID: memberID),
            executions: memberID.map { member in executions.filter { $0.member == member } } ?? executions
        )
    }
}

enum TaskManagerError: LocalizedError {
    case taskServiceNotConfigured

    var errorDescription: String? {
        switch self {
        case .taskServiceNotConfigured:
            return NSLocalizedString("task.error.service_not_configured", comment: "任务服务未配置")
        }
    }
}

enum TaskRepeatEditScope: Sendable {
    case instance
    case plan
}
