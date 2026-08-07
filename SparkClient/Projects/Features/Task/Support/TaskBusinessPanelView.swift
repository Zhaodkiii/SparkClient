import SwiftUI

struct TaskBusinessPanelView: View {
    let task: HealthTask

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(panelTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            switch task.type {
            case .medical:
                medicalPanel
            case .exercise:
                exercisePanel
            case .diet:
                dietPanel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var panelTitle: String {
        switch task.type {
        case .medical: return NSLocalizedString("task.panel.medical", comment: "医疗面板")
        case .exercise: return NSLocalizedString("task.panel.exercise", comment: "运动面板")
        case .diet: return NSLocalizedString("task.panel.diet", comment: "饮食面板")
        }
    }

    @ViewBuilder
    private var medicalPanel: some View {
        if let medical = task.taskMedical {
            detailRow(
                title: NSLocalizedString("task.field.reminder_time", comment: "提醒时间"),
                value: medical.reminderTime.map(formatTime) ?? NSLocalizedString("task.detail.no_reminder", comment: "未设置提醒时间")
            )
            detailRow(
                title: NSLocalizedString("task.field.medical_type", comment: "医疗任务类型"),
                value: medical.medicalTaskType
            )
            if medical.description.isEmpty == false {
                detailRow(
                    title: NSLocalizedString("task.field.description", comment: "描述"),
                    value: medical.description
                )
            }
        } else {
            unavailableText
        }
    }

    @ViewBuilder
    private var exercisePanel: some View {
        if let exercise = task.taskExercise {
            detailRow(
                title: NSLocalizedString("task.field.exercise_type", comment: "运动类型"),
                value: exercise.exerciseType
            )
            detailRow(
                title: NSLocalizedString("task.field.duration", comment: "时长"),
                value: String(format: NSLocalizedString("task.field.duration_minutes", comment: "%d 分钟"), exercise.durationMin)
            )
            detailRow(
                title: NSLocalizedString("task.field.intensity", comment: "强度"),
                value: exercise.intensity
            )
            if exercise.description.isEmpty == false {
                detailRow(
                    title: NSLocalizedString("task.field.description", comment: "描述"),
                    value: exercise.description
                )
            }
        } else {
            unavailableText
        }
    }

    @ViewBuilder
    private var dietPanel: some View {
        if let diet = task.taskDiet {
            detailRow(
                title: NSLocalizedString("task.field.meal_type", comment: "餐次类型"),
                value: diet.mealType
            )
            detailRow(
                title: NSLocalizedString("task.field.calorie_target", comment: "目标热量"),
                value: String(format: NSLocalizedString("task.detail.diet_calories", comment: "%d kcal"), diet.calorieTarget)
            )
            if diet.foodRecommend.isEmpty == false {
                detailRow(
                    title: NSLocalizedString("task.field.food_recommend", comment: "食物推荐"),
                    value: diet.foodRecommend.joined(separator: "、")
                )
            }
            if diet.description.isEmpty == false {
                detailRow(
                    title: NSLocalizedString("task.field.description", comment: "描述"),
                    value: diet.description
                )
            }
        } else {
            unavailableText
        }
    }

    private var unavailableText: some View {
        Text(NSLocalizedString("task.detail.business_unavailable", comment: "业务信息暂不可用"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }

    private func formatTime(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
}
