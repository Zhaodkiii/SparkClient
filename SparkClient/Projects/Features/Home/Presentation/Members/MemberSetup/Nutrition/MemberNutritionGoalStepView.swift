import SwiftUI

struct MemberNutritionGoalStepView: View {
    @Binding var goalMode: MemberNutritionSetupViewModel.GoalMode
    @Binding var activityLevel: MemberNutritionSetupViewModel.ActivityLevel
    @Binding var weeklyTargetKg: Double

    var body: some View {
        MemberSetupSection(title: "目标设置") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("目标模式", selection: $goalMode) {
                    ForEach(MemberNutritionSetupViewModel.GoalMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Picker("活跃水平", selection: $activityLevel) {
                    ForEach(MemberNutritionSetupViewModel.ActivityLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("每周目标")
                    Spacer()
                    TextField("kg", value: $weeklyTargetKg, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }
            .font(.subheadline)
        }
    }
}

private extension MemberNutritionSetupViewModel.ActivityLevel {
    var title: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}
