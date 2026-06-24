import SwiftUI

struct MemberNutritionGoalStepView: View {
    @Binding var goalMode: MemberNutritionSetupViewModel.GoalMode
    @Binding var activityLevel: MemberNutritionSetupViewModel.ActivityLevel
    @Binding var weeklyTargetKg: Double

    var body: some View {
        MemberSetupSection(title: L10n.text("member.setup.nutrition.nutrition.2faa26")) {
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
                    Text(L10n.text("member.setup.nutrition.nutrition.990f7f"))
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
        case .low: return L10n.text("member.setup.medical.nutrition.19ac67");
        case .medium: return L10n.text("member.setup.medical.nutrition.aed1df");
        case .high: return L10n.text("member.setup.medical.nutrition.4296d7");        }
    }
}
