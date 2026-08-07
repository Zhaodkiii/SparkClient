import Foundation

struct TaskDetailModel: Equatable, Sendable {
    let task: HealthTask
    let overdue: Bool
    let canEdit: Bool
    let canExecute: Bool
    let businessTitle: String
    let businessSubtitle: String
    let hasBusinessData: Bool
}

enum TaskDetailModelBuilder {
    static func make(task: HealthTask, now: Date = Date()) -> TaskDetailModel {
        let due = task.dueTime ?? task.startTime ?? .distantFuture
        let overdue = task.status == .pending && due < now

        let businessTitle: String
        let businessSubtitle: String
        let hasBusinessData: Bool

        switch task.type {
        case .medical:
            if let medical = task.taskMedical {
                businessTitle = medical.medicalTaskType
                businessSubtitle = medical.reminderTime.map {
                    DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short)
                } ?? NSLocalizedString("task.detail.no_reminder", comment: "未设置提醒时间")
                hasBusinessData = true
            } else {
                businessTitle = NSLocalizedString("task.type.medical", comment: "医疗")
                businessSubtitle = NSLocalizedString("task.detail.business_unavailable", comment: "业务信息暂不可用")
                hasBusinessData = false
            }
        case .exercise:
            if let exercise = task.taskExercise {
                businessTitle = exercise.exerciseType
                businessSubtitle = String(
                    format: NSLocalizedString("task.detail.exercise_summary", comment: "%d 分钟 · %@"),
                    exercise.durationMin,
                    exercise.intensity
                )
                hasBusinessData = true
            } else {
                businessTitle = NSLocalizedString("task.type.exercise", comment: "运动")
                businessSubtitle = NSLocalizedString("task.detail.business_unavailable", comment: "业务信息暂不可用")
                hasBusinessData = false
            }
        case .diet:
            if let diet = task.taskDiet {
                businessTitle = diet.mealType
                businessSubtitle = String(
                    format: NSLocalizedString("task.detail.diet_calories", comment: "%d kcal"),
                    diet.calorieTarget
                )
                hasBusinessData = true
            } else {
                businessTitle = NSLocalizedString("task.type.diet", comment: "饮食")
                businessSubtitle = NSLocalizedString("task.detail.business_unavailable", comment: "业务信息暂不可用")
                hasBusinessData = false
            }
        }

        return TaskDetailModel(
            task: task,
            overdue: overdue,
            canEdit: task.status != .completed && task.status != .canceled,
            canExecute: task.status == .pending,
            businessTitle: businessTitle,
            businessSubtitle: businessSubtitle,
            hasBusinessData: hasBusinessData
        )
    }
}
