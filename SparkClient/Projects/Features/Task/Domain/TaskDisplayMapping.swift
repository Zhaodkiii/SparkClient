import SwiftUI

enum TaskDisplayMapping {
    static func medicalTaskType(_ rawValue: String) -> String {
        switch rawValue {
        case "health_monitoring":
            return NSLocalizedString("task.medical_type.health_monitoring", comment: "健康监测")
        case "medication":
            return NSLocalizedString("task.medical_type.medication", comment: "用药提醒")
        case "follow_up":
            return NSLocalizedString("task.medical_type.follow_up", comment: "复诊随访")
        case "checkup":
            return NSLocalizedString("task.medical_type.checkup", comment: "体检计划")
        case "report_review":
            return NSLocalizedString("task.medical_type.report_review", comment: "报告解读")
        case "general_medical":
            return NSLocalizedString("task.medical_type.general", comment: "医疗任务")
        default:
            return fallbackDisplayName(rawValue)
        }
    }

    static func exerciseType(_ rawValue: String) -> String {
        switch rawValue {
        case "walking":
            return NSLocalizedString("task.exercise_type.walking", comment: "步行")
        case "running":
            return NSLocalizedString("task.exercise_type.running", comment: "跑步")
        case "cycling":
            return NSLocalizedString("task.exercise_type.cycling", comment: "骑行")
        case "stretching":
            return NSLocalizedString("task.exercise_type.stretching", comment: "拉伸")
        default:
            return fallbackDisplayName(rawValue)
        }
    }

    static func intensity(_ rawValue: String) -> String {
        switch rawValue {
        case "low":
            return NSLocalizedString("task.exercise.intensity.low", comment: "低强度")
        case "medium":
            return NSLocalizedString("task.exercise.intensity.medium", comment: "中等强度")
        case "high":
            return NSLocalizedString("task.exercise.intensity.high", comment: "高强度")
        default:
            return fallbackDisplayName(rawValue)
        }
    }

    static func mealType(_ rawValue: String) -> String {
        switch rawValue {
        case "breakfast":
            return NSLocalizedString("task.diet.meal.breakfast", comment: "早餐")
        case "lunch":
            return NSLocalizedString("task.diet.meal.lunch", comment: "午餐")
        case "dinner":
            return NSLocalizedString("task.diet.meal.dinner", comment: "晚餐")
        case "snack":
            return NSLocalizedString("task.diet.meal.snack", comment: "加餐")
        default:
            return fallbackDisplayName(rawValue)
        }
    }

    private static func fallbackDisplayName(_ rawValue: String) -> String {
        let words = rawValue
            .split(separator: "_")
            .map { part in
                let lower = part.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
        return words.isEmpty ? rawValue : words.joined(separator: " ")
    }
}

extension TaskMedical {
    var medicalTaskTypeDisplayName: String {
        TaskDisplayMapping.medicalTaskType(medicalTaskType)
    }
}

extension TaskExercise {
    var exerciseTypeDisplayName: String {
        TaskDisplayMapping.exerciseType(exerciseType)
    }

    var intensityDisplayName: String {
        TaskDisplayMapping.intensity(intensity)
    }
}

extension TaskDiet {
    var mealTypeDisplayName: String {
        TaskDisplayMapping.mealType(mealType)
    }
}
