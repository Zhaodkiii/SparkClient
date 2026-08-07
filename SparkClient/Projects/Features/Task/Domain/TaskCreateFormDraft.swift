import Foundation

struct TaskCreateFormDraft: Equatable {
    var title: String = ""
    var description: String = ""
    var type: HealthTask.TaskType = .medical
    var startTime: Date = Date()
    var dueTime: Date = Date().addingTimeInterval(3600)
    var repeatType: HealthTask.RepeatType = .none
    var priority: HealthTask.Priority = .medium

    var medicalReminderTime: Date = Date()
    var medicalTaskType: String = "medication"
    var exerciseType: String = "general"
    var exerciseDurationMin: Int = 30
    var exerciseIntensity: String = "medium"
    var dietMealType: String = "breakfast"
    var dietCalorieTarget: Int = 500
    var dietFoodRecommend: String = ""

    func makeCreatePayload(memberID: Int) -> TaskCreatePayload {
        let formatter = ISO8601DateFormatter.taskFormatter
        let medicalPayload: TaskMedicalPayload?
        let exercisePayload: TaskExercisePayload?
        let dietPayload: TaskDietPayload?

        switch type {
        case .medical:
            medicalPayload = TaskMedicalPayload(
                reminderTime: formatter.string(from: medicalReminderTime),
                medicalTaskType: medicalTaskType,
                description: description,
                source: "manual",
                extra: [:]
            )
            exercisePayload = nil
            dietPayload = nil
        case .exercise:
            medicalPayload = nil
            exercisePayload = TaskExercisePayload(
                exerciseType: exerciseType,
                durationMin: exerciseDurationMin,
                intensity: exerciseIntensity,
                description: description,
                source: "manual",
                extra: [:]
            )
            dietPayload = nil
        case .diet:
            medicalPayload = nil
            exercisePayload = nil
            let foods = dietFoodRecommend
                .split(separator: "、")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            dietPayload = TaskDietPayload(
                mealType: dietMealType,
                calorieTarget: dietCalorieTarget,
                foodRecommend: foods,
                description: description,
                source: "manual",
                extra: [:]
            )
        }

        return TaskCreatePayload(
            member: memberID,
            title: title,
            description: description,
            type: type,
            status: .pending,
            startTime: formatter.string(from: startTime),
            dueTime: formatter.string(from: dueTime),
            repeatType: repeatType,
            priority: priority,
            businessType: businessType(for: type),
            businessID: "",
            extra: [:],
            taskMedical: medicalPayload,
            taskExercise: exercisePayload,
            taskDiet: dietPayload
        )
    }

    func makeUpdatePayload() -> TaskUpdatePayload {
        let formatter = ISO8601DateFormatter.taskFormatter
        let medicalPayload: TaskMedicalPayload?
        let exercisePayload: TaskExercisePayload?
        let dietPayload: TaskDietPayload?

        switch type {
        case .medical:
            medicalPayload = TaskMedicalPayload(
                reminderTime: formatter.string(from: medicalReminderTime),
                medicalTaskType: medicalTaskType,
                description: description,
                source: "manual",
                extra: [:]
            )
            exercisePayload = nil
            dietPayload = nil
        case .exercise:
            medicalPayload = nil
            exercisePayload = TaskExercisePayload(
                exerciseType: exerciseType,
                durationMin: exerciseDurationMin,
                intensity: exerciseIntensity,
                description: description,
                source: "manual",
                extra: [:]
            )
            dietPayload = nil
        case .diet:
            medicalPayload = nil
            exercisePayload = nil
            let foods = dietFoodRecommend
                .split(separator: "、")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            dietPayload = TaskDietPayload(
                mealType: dietMealType,
                calorieTarget: dietCalorieTarget,
                foodRecommend: foods,
                description: description,
                source: "manual",
                extra: [:]
            )
        }

        return TaskUpdatePayload(
            title: title,
            description: description,
            status: nil,
            startTime: formatter.string(from: startTime),
            dueTime: formatter.string(from: dueTime),
            repeatType: repeatType,
            priority: priority,
            extra: [:],
            taskMedical: medicalPayload,
            taskExercise: exercisePayload,
            taskDiet: dietPayload
        )
    }

    static func from(task: HealthTask) -> TaskCreateFormDraft {
        var draft = TaskCreateFormDraft()
        draft.title = task.title
        draft.description = task.description
        draft.type = task.type
        draft.startTime = task.startTime ?? Date()
        draft.dueTime = task.dueTime ?? Date().addingTimeInterval(3600)
        draft.repeatType = task.repeatType
        draft.priority = task.priority

        if let medical = task.taskMedical {
            draft.medicalReminderTime = medical.reminderTime ?? draft.startTime
            draft.medicalTaskType = medical.medicalTaskType
        }
        if let exercise = task.taskExercise {
            draft.exerciseType = exercise.exerciseType
            draft.exerciseDurationMin = exercise.durationMin
            draft.exerciseIntensity = exercise.intensity
        }
        if let diet = task.taskDiet {
            draft.dietMealType = diet.mealType
            draft.dietCalorieTarget = diet.calorieTarget
            draft.dietFoodRecommend = diet.foodRecommend.joined(separator: "、")
        }
        return draft
    }

    private func businessType(for type: HealthTask.TaskType) -> String {
        switch type {
        case .medical: return "medical.\(medicalTaskType)"
        case .exercise: return "exercise"
        case .diet: return "diet"
        }
    }
}

enum TaskAITaskDraftParser {
    struct ParsedDraft {
        var form: TaskCreateFormDraft
        var source: HealthTask.Source
    }

    enum ParseError: LocalizedError {
        case invalidJSON
        case missingTitle
        case invalidType
        case invalidPriority
        case invalidRepeatType

        var errorDescription: String? {
            switch self {
            case .invalidJSON:
                return NSLocalizedString("task.ai.error.invalid_json", comment: "JSON 格式无效")
            case .missingTitle:
                return NSLocalizedString("task.ai.error.missing_title", comment: "缺少标题")
            case .invalidType:
                return NSLocalizedString("task.ai.error.invalid_type", comment: "任务类型无效")
            case .invalidPriority:
                return NSLocalizedString("task.ai.error.invalid_priority", comment: "优先级无效")
            case .invalidRepeatType:
                return NSLocalizedString("task.ai.error.invalid_repeat", comment: "重复规则无效")
            }
        }
    }

    static func parse(jsonText: String) throws -> ParsedDraft {
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }

        guard let title = object["title"] as? String, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ParseError.missingTitle
        }

        var form = TaskCreateFormDraft()
        form.title = title
        form.description = (object["description"] as? String) ?? ""

        guard let typeRaw = object["type"] as? String,
              let mappedType = mapType(typeRaw) else {
            throw ParseError.invalidType
        }
        form.type = mappedType

        if let startText = object["startTime"] as? String {
            form.startTime = ISO8601DateFormatter.taskFormatter.date(from: startText) ?? form.startTime
        }
        if let dueText = object["dueTime"] as? String {
            form.dueTime = ISO8601DateFormatter.taskFormatter.date(from: dueText) ?? form.dueTime
        }

        if let repeatRaw = object["repeatType"] as? String {
            guard let repeatType = mapRepeat(repeatRaw) else { throw ParseError.invalidRepeatType }
            form.repeatType = repeatType
        }

        if let priorityRaw = object["priority"] as? String {
            guard let priority = mapPriority(priorityRaw) else { throw ParseError.invalidPriority }
            form.priority = priority
        }

        if let medical = object["taskMedical"] as? [String: Any] {
            if let reminder = medical["reminderTime"] as? String {
                form.medicalReminderTime = ISO8601DateFormatter.taskFormatter.date(from: reminder) ?? form.medicalReminderTime
            }
            form.medicalTaskType = (medical["medicalTaskType"] as? String) ?? form.medicalTaskType
        }

        if let exercise = object["taskExercise"] as? [String: Any] {
            form.exerciseType = (exercise["exerciseType"] as? String) ?? form.exerciseType
            form.exerciseDurationMin = (exercise["durationMin"] as? Int) ?? form.exerciseDurationMin
            form.exerciseIntensity = (exercise["intensity"] as? String) ?? form.exerciseIntensity
        }

        if let diet = object["taskDiet"] as? [String: Any] {
            form.dietMealType = (diet["mealType"] as? String) ?? form.dietMealType
            form.dietCalorieTarget = (diet["calorieTarget"] as? Int) ?? form.dietCalorieTarget
            if let foods = diet["foodRecommend"] as? [String] {
                form.dietFoodRecommend = foods.joined(separator: "、")
            }
        }

        return ParsedDraft(form: form, source: .ai)
    }

    private static func mapType(_ raw: String) -> HealthTask.TaskType? {
        switch raw.lowercased() {
        case "medical": return .medical
        case "exercise": return .exercise
        case "diet": return .diet
        default: return nil
        }
    }

    private static func mapRepeat(_ raw: String) -> HealthTask.RepeatType? {
        switch raw.lowercased() {
        case "none": return HealthTask.RepeatType.none
        case "daily": return .daily
        case "weekly": return .weekly
        default: return nil
        }
    }

    private static func mapPriority(_ raw: String) -> HealthTask.Priority? {
        switch raw.lowercased() {
        case "high": return .high
        case "medium": return .medium
        case "low": return .low
        default: return nil
        }
    }
}
