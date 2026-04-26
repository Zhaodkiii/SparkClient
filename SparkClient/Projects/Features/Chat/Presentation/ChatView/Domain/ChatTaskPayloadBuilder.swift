import Foundation

/// 任务卡 -> Task 创建参数转换器。
/// 只负责数据拼装，不承担网络副作用。
enum ChatTaskPayloadBuilder {
    static func build(from card: TaskCard) -> TaskCreatePayload {
        let base = parseJSONObject(card.taskPayload["task"])
        let subMedical = parseJSONObject(card.taskPayload["task_medical"])
        let subExercise = parseJSONObject(card.taskPayload["task_exercise"])
        let subDiet = parseJSONObject(card.taskPayload["task_diet"])

        let startText = stringValue(base["start_time"]) ?? card.startTime.map { iso8601String($0) }
        let dueText = stringValue(base["due_time"]) ?? card.dueTime.map { iso8601String($0) }
        let repeatTypeRaw = intValue(base["repeat_type"]) ?? card.repeatType.rawValue
        let priorityRaw = intValue(base["priority"]) ?? card.priority.rawValue

        return TaskCreatePayload(
            member: intValue(base["member"]) ?? intValue(base["member_id"]) ?? card.member ?? 0,
            title: stringValue(base["title"]) ?? card.title,
            description: stringValue(base["description"]) ?? card.description,
            type: card.type,
            status: .pending,
            startTime: startText,
            dueTime: dueText,
            repeatType: HealthTask.RepeatType(rawValue: repeatTypeRaw) ?? .none,
            priority: HealthTask.Priority(rawValue: priorityRaw) ?? .medium,
            businessType: stringValue(base["business_type"]) ?? card.businessType,
            businessID: stringValue(base["business_id"]) ?? card.businessID,
            extra: [:],
            taskMedical: buildMedicalPayload(from: subMedical, fallback: card),
            taskExercise: buildExercisePayload(from: subExercise, fallback: card),
            taskDiet: buildDietPayload(from: subDiet, fallback: card)
        )
    }

    private static func buildMedicalPayload(from json: [String: Any], fallback card: TaskCard) -> TaskMedicalPayload? {
        guard card.type == .medical else { return nil }
        return TaskMedicalPayload(
            reminderTime: stringValue(json["reminder_time"]) ?? card.startTime.map { iso8601String($0) },
            medicalTaskType: stringValue(json["medical_task_type"]) ?? card.title,
            description: stringValue(json["description"]) ?? card.description,
            source: "ai",
            extra: [:]
        )
    }

    private static func buildExercisePayload(from json: [String: Any], fallback card: TaskCard) -> TaskExercisePayload? {
        guard card.type == .exercise else { return nil }
        return TaskExercisePayload(
            exerciseType: stringValue(json["exercise_type"]) ?? card.title,
            durationMin: intValue(json["duration_min"]) ?? 30,
            intensity: stringValue(json["intensity"]) ?? "medium",
            description: stringValue(json["description"]) ?? card.description,
            source: "ai",
            extra: [:]
        )
    }

    private static func buildDietPayload(from json: [String: Any], fallback card: TaskCard) -> TaskDietPayload? {
        guard card.type == .diet else { return nil }
        var foodRecommend = [String]()
        if let array = json["food_recommend"] as? [String] {
            foodRecommend = array
        } else if let text = stringValue(json["food_recommend"]), text.isEmpty == false {
            foodRecommend = [text]
        }
        if foodRecommend.isEmpty {
            foodRecommend = [card.description]
        }
        return TaskDietPayload(
            mealType: stringValue(json["meal_type"]) ?? "dinner",
            calorieTarget: intValue(json["calorie_target"]) ?? 1800,
            foodRecommend: foodRecommend,
            description: stringValue(json["description"]) ?? card.description,
            source: "ai",
            extra: [:]
        )
    }

    private static func parseJSONObject(_ text: String?) -> [String: Any] {
        guard let text,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        if let stringValue = value as? String { return Int(stringValue) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let intValue = value as? Int { return "\(intValue)" }
        if let doubleValue = value as? Double { return "\(doubleValue)" }
        return nil
    }

    nonisolated private static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter.string(
            from: date,
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current,
            formatOptions: [.withInternetDateTime, .withFractionalSeconds]
        )
    }
}
