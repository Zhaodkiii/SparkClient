import SwiftUI

struct MemberNutritionMacroGoalStepView: View {
    @Binding var targetCalories: Double
    @Binding var carbohydratePercent: Double
    @Binding var proteinPercent: Double
    @Binding var fatPercent: Double
    @Binding var mealDistribution: [String: Double]

    var body: some View {
        MemberSetupSection(title: "营养目标") {
            VStack(alignment: .leading, spacing: 14) {
                macroRow(title: "碳水化合物", percent: $carbohydratePercent)
                macroRow(title: "蛋白质", percent: $proteinPercent)
                macroRow(title: "脂肪", percent: $fatPercent)

                Divider()

                mealRow(title: "早餐", key: "breakfast")
                mealRow(title: "午餐", key: "lunch")
                mealRow(title: "晚餐", key: "dinner")
                mealRow(title: "小吃", key: "snack")
            }
            .font(.subheadline)
        }
    }

    private func macroRow(title: String, percent: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("%", value: percent, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }

    private func mealRow(title: String, key: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("%", value: binding(for: key), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }

    private func binding(for key: String) -> Binding<Double> {
        Binding(
            get: { mealDistribution[key] ?? 0 },
            set: { mealDistribution[key] = $0 }
        )
    }
}

