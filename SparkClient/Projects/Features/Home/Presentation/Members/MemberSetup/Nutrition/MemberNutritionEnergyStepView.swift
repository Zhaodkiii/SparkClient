import SwiftUI

struct MemberNutritionEnergyStepView: View {
    @Binding var targetCalories: Double
    let suggestedCalories: Double?
    let bmrKcal: Double?
    let tdeeKcal: Double?
    let activityBurnKcal: Double?
    let energyDeltaKcal: Double?
    let warnings: [String]
    let onRecalculate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MemberSetupSection(title: L10n.text("member.setup.nutrition.nutrition.5f3406")) {
                VStack(alignment: .leading, spacing: 14) {
                    metricRow("建议摄入", value: formatEnergy(suggestedCalories))
                    metricRow("基础代谢", value: formatEnergy(bmrKcal))
                    metricRow("维持热量", value: formatEnergy(tdeeKcal))
                    metricRow("日常活动估算", value: formatEnergy(activityBurnKcal))
                    metricRow("每日热量差", value: formatEnergy(energyDeltaKcal))

                    Divider()

                    HStack {
                        Text(L10n.text("member.setup.nutrition.nutrition.c7c48e"))
                        Spacer()
                        TextField("kcal", value: $targetCalories, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }

                    Button(L10n.text("member.setup.nutrition.nutrition.50b876")) {
                        onRecalculate()
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .font(.subheadline)
            }

            if warnings.isEmpty == false {
                MemberSetupSection(title: L10n.text("member.setup.nutrition.nutrition.02d981")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(warnings, id: \.self) { warning in
                            Text(warning)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func formatEnergy(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(Int(value.rounded())) 千卡"
    }
}
