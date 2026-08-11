import Foundation

struct TaskDetailKeyValueItem: Identifiable, Equatable, Sendable {
    let title: String
    let value: String

    var id: String { "\(title)|\(value)" }
}

struct TaskDetailPreviewModel: Equatable, Sendable {
    let title: String
    let description: String
    let type: HealthTask.TaskType
    let statusText: String
    let sourceText: String
    let repeatText: String
    let priorityText: String
    let startTimeText: String?
    let dueTimeText: String?
    let businessTypeText: String
    let businessIDText: String
    let businessRows: [TaskDetailKeyValueItem]
}

struct TaskCardPreviewEditResult: Equatable, Sendable {
    let draft: TaskCreateFormDraft
    let updatedAt: Date
}

enum TaskCardPreviewMapper {
    static func makeDisplayModel(from card: TaskCard) -> TaskDetailPreviewModel {
        let taskJSON = parseJSONObject(card.taskPayload["task"])
        let subMedical = parseJSONObject(card.taskPayload["task_medical"])
        let subExercise = parseJSONObject(card.taskPayload["task_exercise"])
        let subDiet = parseJSONObject(card.taskPayload["task_diet"])

        let title = stringValue(taskJSON["title"]) ?? card.title
        let description = stringValue(taskJSON["description"]) ?? card.description
        let statusText = statusText(for: card.status)
        let sourceText = sourceText(for: card.source)
        let repeatText = repeatText(for: card.repeatType)
        let priorityText = priorityText(for: card.priority)
        let startTimeText = stringValue(taskJSON["start_time"]).map(formatDateString)
            ?? card.startTime.map(formatDate)
        let dueTimeText = stringValue(taskJSON["due_time"]).map(formatDateString)
            ?? card.dueTime.map(formatDate)
        let businessTypeText = stringValue(taskJSON["business_type"]) ?? card.businessType.taskBusinessTypeDisplayName
        let businessIDText = stringValue(taskJSON["business_id"]) ?? card.businessID

        let businessRows: [TaskDetailKeyValueItem]
        switch card.type {
        case .medical:
            businessRows = medicalRows(taskJSON: taskJSON, subJSON: subMedical, card: card)
        case .exercise:
            businessRows = exerciseRows(subJSON: subExercise, card: card)
        case .diet:
            businessRows = dietRows(subJSON: subDiet, card: card)
        }

        return TaskDetailPreviewModel(
            title: title,
            description: description,
            type: card.type,
            statusText: statusText,
            sourceText: sourceText,
            repeatText: repeatText,
            priorityText: priorityText,
            startTimeText: startTimeText,
            dueTimeText: dueTimeText,
            businessTypeText: businessTypeText,
            businessIDText: businessIDText,
            businessRows: businessRows
        )
    }

    static func makeDraft(from card: TaskCard) -> TaskCreateFormDraft {
        let taskJSON = parseJSONObject(card.taskPayload["task"])
        let subMedical = parseJSONObject(card.taskPayload["task_medical"])
        let subExercise = parseJSONObject(card.taskPayload["task_exercise"])
        let subDiet = parseJSONObject(card.taskPayload["task_diet"])

        var draft = TaskCreateFormDraft()
        draft.title = stringValue(taskJSON["title"]) ?? card.title
        draft.description = stringValue(taskJSON["description"]) ?? card.description
        draft.type = card.type
        draft.startTime = stringValue(taskJSON["start_time"]).flatMap(dateValue)
            ?? card.startTime
            ?? Date()
        draft.dueTime = stringValue(taskJSON["due_time"]).flatMap(dateValue)
            ?? card.dueTime
            ?? draft.startTime.addingTimeInterval(3600)
        draft.repeatType = HealthTask.RepeatType(rawValue: intValue(taskJSON["repeat_type"]) ?? card.repeatType.rawValue) ?? card.repeatType
        draft.priority = HealthTask.Priority(rawValue: intValue(taskJSON["priority"]) ?? card.priority.rawValue) ?? card.priority

        switch card.type {
        case .medical:
            draft.medicalReminderTime = stringValue(subMedical["reminder_time"]).flatMap(dateValue)
                ?? stringValue(taskJSON["start_time"]).flatMap(dateValue)
                ?? card.startTime
                ?? draft.startTime
            draft.medicalTaskType = stringValue(subMedical["medical_task_type"]) ?? card.title
        case .exercise:
            draft.exerciseType = stringValue(subExercise["exercise_type"]) ?? card.title
            draft.exerciseDurationMin = intValue(subExercise["duration_min"]) ?? 30
            draft.exerciseIntensity = stringValue(subExercise["intensity"]) ?? "medium"
        case .diet:
            draft.dietMealType = stringValue(subDiet["meal_type"]) ?? "dinner"
            draft.dietCalorieTarget = intValue(subDiet["calorie_target"]) ?? 1800
            if let array = subDiet["food_recommend"] as? [String] {
                draft.dietFoodRecommend = array.joined(separator: "、")
            } else if let text = stringValue(subDiet["food_recommend"]) {
                draft.dietFoodRecommend = text
            } else {
                draft.dietFoodRecommend = card.description
            }
        }

        return draft
    }

    static func applying(_ draft: TaskCreateFormDraft, to card: TaskCard) -> TaskCard {
        var next = card
        let formatter = ISO8601DateFormatter.taskFormatter
        var previewTaskJSON = jsonObject(from: next.taskPayload["task"])

        next.title = draft.title
        next.description = draft.description
        next.type = draft.type
        next.startTime = draft.startTime
        next.dueTime = draft.dueTime
        next.repeatType = draft.repeatType
        next.priority = draft.priority
        next.businessType = draft.previewBusinessType
        previewTaskJSON["title"] = draft.title
        previewTaskJSON["description"] = draft.description
        previewTaskJSON["type"] = draft.type.rawValue
        previewTaskJSON["start_time"] = formatter.string(from: draft.startTime)
        previewTaskJSON["due_time"] = formatter.string(from: draft.dueTime)
        previewTaskJSON["repeat_type"] = draft.repeatType.rawValue
        previewTaskJSON["priority"] = draft.priority.rawValue
        previewTaskJSON["business_type"] = draft.previewBusinessType
        previewTaskJSON["business_id"] = next.businessID
        next.taskPayload["task"] = jsonString(from: previewTaskJSON) ?? next.taskPayload["task"] ?? "{}"
        switch draft.type {
        case .medical:
            next.taskPayload["task_medical"] = jsonString(from: [
                "reminder_time": formatter.string(from: draft.medicalReminderTime),
                "medical_task_type": draft.medicalTaskType,
                "description": draft.description,
                "source": "ai"
            ]) ?? next.taskPayload["task_medical"] ?? "{}"
        case .exercise:
            next.taskPayload["task_exercise"] = jsonString(from: [
                "exercise_type": draft.exerciseType,
                "duration_min": draft.exerciseDurationMin,
                "intensity": draft.exerciseIntensity,
                "description": draft.description,
                "source": "ai"
            ]) ?? next.taskPayload["task_exercise"] ?? "{}"
        case .diet:
            let foods = draft.dietFoodRecommend
                .split(separator: "、")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            next.taskPayload["task_diet"] = jsonString(from: [
                "meal_type": draft.dietMealType,
                "calorie_target": draft.dietCalorieTarget,
                "food_recommend": foods,
                "description": draft.description,
                "source": "ai"
            ]) ?? next.taskPayload["task_diet"] ?? "{}"
        }
        next.updatedAt = Date()
        next.status = .pending
        next.confirmedTask = nil
        return next
    }

    private static func medicalRows(taskJSON: [String: Any], subJSON: [String: Any], card: TaskCard) -> [TaskDetailKeyValueItem] {
        [
            TaskDetailKeyValueItem(
                title: NSLocalizedString("task.field.reminder_time", comment: "提醒时间"),
            value: stringValue(subJSON["reminder_time"]).map(formatDateString)
                ?? card.startTime.map(formatDate)
                ?? NSLocalizedString("task.detail.no_reminder", comment: "未设置提醒时间")
            ),
            TaskDetailKeyValueItem(
                title: NSLocalizedString("task.field.medical_type", comment: "医疗任务类型"),
                value: TaskDisplayMapping.medicalTaskType(stringValue(subJSON["medical_task_type"]) ?? stringValue(taskJSON["medical_task_type"]) ?? card.title)
            ),
            TaskDetailKeyValueItem(
                title: NSLocalizedString("task.field.description", comment: "描述"),
                value: stringValue(subJSON["description"]) ?? card.description
            )
        ]
    }

    private static func exerciseRows(subJSON: [String: Any], card: TaskCard) -> [TaskDetailKeyValueItem] {
        [
            TaskDetailKeyValueItem(
                title: NSLocalizedString("task.field.exercise_type", comment: "运动类型"),
                value: TaskDisplayMapping.exerciseType(stringValue(subJSON["exercise_type"]) ?? card.title)
            ),
            TaskDetailKeyValueItem(
                title: NSLocalizedString("task.field.duration", comment: "时长"),
                value: String(format: NSLocalizedString("task.field.duration_minutes", comment: "%d 分钟"), intValue(subJSON["duration_min"]) ?? 30)
            ),
            TaskDetailKeyValueItem(
                title: NSLocalizedString("task.field.intensity", comment: "强度"),
                value: TaskDisplayMapping.intensity(stringValue(subJSON["intensity"]) ?? "medium")
            ),
            TaskDetailKeyValueItem(
                title: NSLocalizedString("task.field.description", comment: "描述"),
                value: stringValue(subJSON["description"]) ?? card.description
            )
        ]
    }

    private static func dietRows(subJSON: [String: Any], card: TaskCard) -> [TaskDetailKeyValueItem] {
        let foods: String
        if let array = subJSON["food_recommend"] as? [String] {
            foods = array.joined(separator: "、")
        } else {
            foods = stringValue(subJSON["food_recommend"]) ?? card.description
        }
        return [
            TaskDetailKeyValueItem(
                title: NSLocalizedString("task.field.meal_type", comment: "餐次类型"),
                value: TaskDisplayMapping.mealType(stringValue(subJSON["meal_type"]) ?? card.title)
            ),
            TaskDetailKeyValueItem(
                title: NSLocalizedString("task.field.calorie_target", comment: "目标热量"),
                value: String(format: NSLocalizedString("task.detail.diet_calories", comment: "%d kcal"), intValue(subJSON["calorie_target"]) ?? 1800)
            ),
            TaskDetailKeyValueItem(
                title: NSLocalizedString("task.field.food_recommend", comment: "食物推荐"),
                value: foods
            ),
            TaskDetailKeyValueItem(
                title: NSLocalizedString("task.field.description", comment: "描述"),
                value: stringValue(subJSON["description"]) ?? card.description
            )
        ]
    }

    private static func statusText(for status: TaskCard.CardStatus) -> String {
        switch status {
        case .pending:
            return NSLocalizedString("task.preview.status.pending", comment: "待保存")
        case .confirmed:
            return NSLocalizedString("task.card.status.confirmed", comment: "已创建")
        case .ignored:
            return NSLocalizedString("task.card.status.ignored", comment: "已忽略")
        case .expired:
            return NSLocalizedString("task.card.status.expired", comment: "已过期")
        }
    }

    private static func sourceText(for source: HealthTask.Source) -> String {
        switch source {
        case .manual: return NSLocalizedString("task.source.manual", comment: "手动")
        case .ai: return NSLocalizedString("task.source.ai", comment: "AI 生成")
        case .report: return NSLocalizedString("task.source.report", comment: "报告")
        }
    }

    private static func repeatText(for repeatType: HealthTask.RepeatType) -> String {
        switch repeatType {
        case .none: return NSLocalizedString("task.repeat.none", comment: "不重复")
        case .daily: return NSLocalizedString("task.repeat.daily", comment: "每日")
        case .weekly: return NSLocalizedString("task.repeat.weekly", comment: "每周")
        }
    }

    private static func priorityText(for priority: HealthTask.Priority) -> String {
        switch priority {
        case .high: return NSLocalizedString("task.priority.high", comment: "高优先级")
        case .medium: return NSLocalizedString("task.priority.medium", comment: "中优先级")
        case .low: return NSLocalizedString("task.priority.low", comment: "低优先级")
        }
    }

    private static func formatDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    private static func formatDateString(_ text: String) -> String {
        if let date = dateValue(text) {
            return formatDate(date)
        }
        return text
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

    private static func jsonObject(from text: String?) -> [String: Any] {
        parseJSONObject(text)
    }

    private static func jsonString(from object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
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

    private static func dateValue(_ text: String) -> Date? {
        if let date = ISO8601DateFormatter.taskFormatter.date(from: text) { return date }
        if let date = ISO8601DateFormatter().date(from: text) { return date }
        return nil
    }
}
