import Foundation

enum TaskExecutionStatus: String, Codable, CaseIterable, Sendable {
    case done
    case skipped
    case failed

    var displayName: String {
        switch self {
        case .done:
            return NSLocalizedString("task.execution.done", comment: "完成")
        case .skipped:
            return NSLocalizedString("task.execution.skipped", comment: "跳过")
        case .failed:
            return NSLocalizedString("task.execution.failed", comment: "失败")
        }
    }

    init?(serverValue: Int) {
        switch serverValue {
        case 1: self = .done
        case 2: self = .skipped
        case 3: self = .failed
        default: return nil
        }
    }

    var serverValue: Int {
        switch self {
        case .done: return 1
        case .skipped: return 2
        case .failed: return 3
        }
    }
}

struct TaskExecutionRecord: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    let task: Int
    let member: Int
    var businessType: String
    var businessId: String
    var status: TaskExecutionStatus
    var executedAt: Date
    var value: [String: String]
    var notes: String

    var businessID: String {
        get { businessId }
        set { businessId = newValue }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        task = try container.decode(Int.self, forKey: .task)
        member = try container.decode(Int.self, forKey: .member)
        businessType = try container.decodeIfPresent(String.self, forKey: .businessType) ?? ""
        businessId = try container.decodeIfPresent(String.self, forKey: .businessId) ?? ""
        let statusRaw = try container.decode(Int.self, forKey: .status)
        guard let parsed = TaskExecutionStatus(serverValue: statusRaw) else {
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Unknown execution status")
        }
        status = parsed
        executedAt = try container.decode(Date.self, forKey: .executedAt)
        value = (try? container.decode([String: String].self, forKey: .value)) ?? [:]
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

struct TaskExecutionDraft: Sendable {
    let status: TaskExecutionStatus
    let executedAt: Date
    let value: [String: String]
    let notes: String?
    let businessType: String
    let businessID: String

    func makePayload() -> TaskExecutionSubmitPayload {
        TaskExecutionSubmitPayload(
            status: status.rawValue,
            executedAt: ISO8601DateFormatter.taskFormatter.string(from: executedAt),
            value: value,
            notes: notes,
            businessType: businessType,
            businessID: businessID
        )
    }

    static func defaultValue(for task: HealthTask, status: TaskExecutionStatus) -> [String: String] {
        let now = ISO8601DateFormatter.taskFormatter.string(from: Date())
        switch task.type {
        case .medical:
            return [
                "actual_taken_at": now,
                "result": status == .done ? "taken" : status.rawValue
            ]
        case .exercise:
            let duration = task.taskExercise.map { String($0.durationMin) } ?? "0"
            let intensity = task.taskExercise?.intensity ?? "medium"
            return [
                "duration_min": duration,
                "intensity": intensity,
                "result": status.rawValue
            ]
        case .diet:
            let meal = task.taskDiet?.mealType ?? "meal"
            let target = task.taskDiet.map { String($0.calorieTarget) } ?? "0"
            return [
                "meal_type": meal,
                "calorie_target": target,
                "result": status.rawValue
            ]
        }
    }
}

enum TaskExecutionDraftBuilder {
    static func make(for task: HealthTask, status: TaskExecutionStatus, notes: String? = nil) -> TaskExecutionDraft {
        TaskExecutionDraft(
            status: status,
            executedAt: Date(),
            value: TaskExecutionDraft.defaultValue(for: task, status: status),
            notes: notes,
            businessType: task.businessType,
            businessID: task.businessID
        )
    }
}

extension ISO8601DateFormatter {
    static let taskFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
