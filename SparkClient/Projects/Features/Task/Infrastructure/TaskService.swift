import Foundation

/// 任务模块网络服务：统一封装任务 REST API 与增量同步。
struct TaskService {
    private let configuration: SparkBackendConfiguration
    private let logger: Logger

    private static let syncCursorKey = "task.sync.last_time"

    init(configuration: SparkBackendConfiguration, logger: Logger = ConsoleLogger()) {
        self.configuration = configuration
        self.logger = logger
    }

    var lastSyncTime: Date? {
        get {
            guard let text = UserDefaults.standard.string(forKey: Self.syncCursorKey) else { return nil }
            return ISO8601DateFormatter.taskFormatter.date(from: text)
        }
        nonmutating set {
            let text = newValue.map { ISO8601DateFormatter.taskFormatter.string(from: $0) }
            UserDefaults.standard.setValue(text, forKey: Self.syncCursorKey)
        }
    }

    // MARK: - 任务 CRUD

    func fetchTasks(memberID: Int?, since: Date?) async throws -> [HealthTask] {
        var query: [URLQueryItem] = []
        if let memberID {
            query.append(URLQueryItem(name: "member_id", value: "\(memberID)"))
        }
        if let since {
            query.append(URLQueryItem(name: "since", value: ISO8601DateFormatter.taskFormatter.string(from: since)))
        }

        let operation = CacheableSparkNetworkOperation(
            name: "Task.FetchList",
            apiName: "TaskService",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/tasks/",
                queryItems: query,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "task.list",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try decodeWrapped([HealthTask].self, from: response)
    }

    func createTask(payload: TaskCreatePayload) async throws -> HealthTask {
        let operation = CacheableSparkNetworkOperation(
            name: "Task.Create",
            apiName: "TaskService",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/tasks/",
                body: .json(AnyEncodable(payload)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "task.create",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .veryHigh
                )
            )
        )
        let response = try await configuration.execute(operation)
        let task = try decodeWrapped(HealthTask.self, from: response)
        logger.info("任务创建成功 task_id=\(task.id)", module: .network)
        return task
    }

    func updateTask(taskID: Int, payload: TaskUpdatePayload) async throws -> HealthTask {
        let operation = CacheableSparkNetworkOperation(
            name: "Task.Update",
            apiName: "TaskService",
            request: SparkNetworkRequest(
                method: .patch,
                path: "/api/v1/tasks/\(taskID)/",
                body: .json(AnyEncodable(payload)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "task.update.\(taskID)",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try decodeWrapped(HealthTask.self, from: response)
    }

    func completeTask(taskID: Int, payload: TaskExecutionPayload? = nil) async throws -> TaskStatusSyncItem {
        let operation = CacheableSparkNetworkOperation(
            name: "Task.Complete",
            apiName: "TaskService",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/tasks/\(taskID)/complete/",
                body: .json(AnyEncodable(payload ?? TaskExecutionPayload())),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "task.complete.\(taskID)",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .veryHigh
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try decodeWrapped(TaskStatusSyncItem.self, from: response)
    }

    func fetchExecutions(taskID: Int) async throws -> [TaskExecutionRecord] {
        let operation = CacheableSparkNetworkOperation(
            name: "Task.FetchExecutions",
            apiName: "TaskService",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/tasks/\(taskID)/executions/",
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "task.executions.\(taskID)",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try decodeWrapped([TaskExecutionRecord].self, from: response)
    }

    func submitExecution(taskID: Int, payload: TaskExecutionSubmitPayload) async throws -> TaskExecutionRecord {
        let operation = CacheableSparkNetworkOperation(
            name: "Task.SubmitExecution",
            apiName: "TaskService",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/tasks/\(taskID)/executions/",
                body: .json(AnyEncodable(payload)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "task.execution.submit.\(taskID)",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .veryHigh
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try decodeWrapped(TaskExecutionRecord.self, from: response)
    }

    func cancelTask(taskID: Int) async throws -> TaskStatusSyncItem {
        let operation = CacheableSparkNetworkOperation(
            name: "Task.Cancel",
            apiName: "TaskService",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/tasks/\(taskID)/cancel/",
                body: .json(AnyEncodable(EmptyPayload())),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "task.cancel.\(taskID)",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .veryHigh
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try decodeWrapped(TaskStatusSyncItem.self, from: response)
    }

    // MARK: - 增量同步

    func sync(memberID: Int?, since: Date?) async throws -> TaskSyncPayload {
        var query: [URLQueryItem] = []
        if let memberID {
            query.append(URLQueryItem(name: "member_id", value: "\(memberID)"))
        }
        if let since {
            query.append(URLQueryItem(name: "since", value: ISO8601DateFormatter.taskFormatter.string(from: since)))
        }

        let operation = CacheableSparkNetworkOperation(
            name: "Task.Sync",
            apiName: "TaskService",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/tasks/sync/",
                queryItems: query,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "task.sync",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .veryHigh
                )
            )
        )

        let response = try await configuration.execute(operation)
        let payload = try decodeWrapped(TaskSyncPayload.self, from: response)
        lastSyncTime = payload.serverTime
        logger.info("任务增量同步完成 tasks=\(payload.tasks.count)", module: .network)
        return payload
    }

    // MARK: - Decode

    private func decodeWrapped<T: Decodable>(_ type: T.Type, from response: SparkNetworkResponse) throws -> T {
        let decoder = JSONDecoder.default
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.taskFormatter.date(from: value) {
                return date
            }
            if let fallback = ISO8601DateFormatter().date(from: value) {
                return fallback
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        return try APIResponseDecoder.decodeWrappedData(type, from: response, decoder: decoder)
    }
}

// MARK: - 请求/响应模型

nonisolated struct TaskCreatePayload: Encodable, Sendable {
    let member: Int
    let title: String
    let description: String
    let type: HealthTask.TaskType
    let status: HealthTask.TaskStatus
    let startTime: String?
    let dueTime: String?
    let repeatType: HealthTask.RepeatType
    let priority: HealthTask.Priority
    let businessType: String
    let businessID: String
    let extra: [String: String]

    let taskMedical: TaskMedicalPayload?
    let taskExercise: TaskExercisePayload?
    let taskDiet: TaskDietPayload?

}

nonisolated struct TaskUpdatePayload: Encodable, Sendable {
    let title: String?
    let description: String?
    let status: HealthTask.TaskStatus?
    let startTime: String?
    let dueTime: String?
    let repeatType: HealthTask.RepeatType?
    let priority: HealthTask.Priority?
    let extra: [String: String]?

    let taskMedical: TaskMedicalPayload?
    let taskExercise: TaskExercisePayload?
    let taskDiet: TaskDietPayload?

}

nonisolated struct TaskMedicalPayload: Encodable, Sendable {
    let reminderTime: String?
    let medicalTaskType: String
    let description: String
    let source: String
    let extra: [String: String]

}

nonisolated struct TaskExercisePayload: Encodable, Sendable {
    let exerciseType: String
    let durationMin: Int
    let intensity: String
    let description: String
    let source: String
    let extra: [String: String]

}

nonisolated struct TaskDietPayload: Encodable, Sendable {
    let mealType: String
    let calorieTarget: Int
    let foodRecommend: [String]
    let description: String
    let source: String
    let extra: [String: String]

}

nonisolated struct TaskExecutionSubmitPayload: Encodable, Sendable {
    let status: String
    let executedAt: String
    let value: [String: String]
    let notes: String?
    let businessType: String
    let businessID: String
}

nonisolated struct TaskExecutionPayload: Encodable, Sendable {
    let executedAt: String?
    let value: [String: String]?
    let notes: String?
    let businessType: String?
    let businessID: String?

    init(
        executedAt: String? = nil,
        value: [String: String]? = nil,
        notes: String? = nil,
        businessType: String? = nil,
        businessID: String? = nil
    ) {
        self.executedAt = executedAt
        self.value = value
        self.notes = notes
        self.businessType = businessType
        self.businessID = businessID
    }

}

nonisolated private struct EmptyPayload: Encodable, Sendable {}
