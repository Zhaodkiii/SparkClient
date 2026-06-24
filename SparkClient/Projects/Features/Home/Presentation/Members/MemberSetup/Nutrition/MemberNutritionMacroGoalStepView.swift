import SwiftUI

struct MemberNutritionMacroGoalStepView: View {
    @Binding var targetCalories: Double
    @Binding var carbohydratePercent: Double
    @Binding var proteinPercent: Double
    @Binding var fatPercent: Double
    @Binding var mealDistribution: [String: Double]

    var body: some View {
        MemberSetupSection(title: L10n.text("member.setup.nutrition.nutrition.3bad9a")) {
            VStack(alignment: .leading, spacing: 14) {
                macroRow(title: L10n.text("member.setup.nutrition.nutrition.d57f7d"), percent: $carbohydratePercent)
                macroRow(title: L10n.text("member.setup.nutrition.nutrition.14a64e"), percent: $proteinPercent)
                macroRow(title: L10n.text("member.setup.nutrition.nutrition.3d7c0e"), percent: $fatPercent)

                Divider()

                mealRow(title: L10n.text("member.setup.nutrition.nutrition.edb336"), key: "breakfast")
                mealRow(title: L10n.text("member.setup.nutrition.nutrition.3cc4b7"), key: "lunch")
                mealRow(title: L10n.text("member.setup.nutrition.nutrition.96a6ae"), key: "dinner")
                mealRow(title: L10n.text("member.setup.nutrition.nutrition.cb0420"), key: "snack")
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

