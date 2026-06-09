import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct NutritionOverviewGridCard: View {
    let data: NutritionOverviewGridData

    var body: some View {
        NutritionCardContainer {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    gridCell(
                        value: NutritionFormatting.energyKcal(data.energyKcal),
                        titleKey: "nutrition.macro.energy"
                    )
                    dividerVertical
                    gridCell(
                        value: NutritionFormatting.grams(data.carbohydrateGrams),
                        titleKey: "nutrition.macro.carbohydrate"
                    )
                }
                dividerHorizontal
                HStack(spacing: 0) {
                    gridCell(
                        value: NutritionFormatting.grams(data.proteinGrams),
                        titleKey: "nutrition.macro.protein"
                    )
                    dividerVertical
                    gridCell(
                        value: NutritionFormatting.grams(data.fatGrams),
                        titleKey: "nutrition.macro.fat"
                    )
                }
            }
        }
    }

    private var dividerHorizontal: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(height: 1)
    }

    private var dividerVertical: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(width: 1)
    }

    private func gridCell(value: String, titleKey: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(L10n.text(titleKey))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

struct NutritionMacroProgressCard: View {
    let titleKey: String
    let data: NutritionMacroProgressCardData

    var body: some View {
        NutritionCardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text(titleKey))
                    .font(.subheadline.weight(.semibold))

                progressRow(
                    titleKey: "nutrition.macro.energy",
                    progress: data.energy,
                    unit: "kcal"
                )
                progressRow(
                    titleKey: "nutrition.macro.carbohydrate",
                    progress: data.carbohydrate,
                    unit: "g"
                )
                progressRow(
                    titleKey: "nutrition.macro.protein",
                    progress: data.protein,
                    unit: "g"
                )
                progressRow(
                    titleKey: "nutrition.macro.fat",
                    progress: data.fat,
                    unit: "g"
                )
            }
        }
    }

    private func progressRow(titleKey: String, progress: NutritionMacroProgress, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.text(titleKey))
                    .font(.subheadline)
                Spacer()
                Text("\(NutritionFormatting.compactEnergy(progress.current)) / \(NutritionFormatting.compactEnergy(progress.target)) \(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progressFraction(progress))
                .tint(Color(uiColor: .systemGreen))
        }
    }

    private func progressFraction(_ progress: NutritionMacroProgress) -> Double {
        guard progress.target > 0 else { return 0 }
        return Swift.min(progress.current / progress.target, 1)
    }
}

struct NutritionDetailInfoCard: View {
    let titleKey: String
    let data: NutritionDetailInfoData

    var body: some View {
        NutritionCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text(titleKey))
                    .font(.subheadline.weight(.semibold))

                ForEach(data.groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(group.title))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(group.rows) { row in
                            HStack {
                                Text(L10n.text(row.title))
                                    .font(.subheadline)
                                Spacer()
                                Text(row.valueText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct NutritionMacroRatioBarChartCard: View {
    let titleKey: String
    let data: NutritionMacroRatioChartData

    var body: some View {
        NutritionCardContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text(titleKey))
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 16) {
                    legendDot(color: Color(uiColor: .systemGreen), labelKey: "nutrition.chart.current")
                    legendDot(color: Color(uiColor: .systemGray3), labelKey: "nutrition.chart.target")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(alignment: .bottom, spacing: 24) {
                    chartColumn(titleKey: "nutrition.macro.carbohydrate", pair: data.carbohydrate)
                    chartColumn(titleKey: "nutrition.macro.protein", pair: data.protein)
                    chartColumn(titleKey: "nutrition.macro.fat", pair: data.fat)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func legendDot(color: Color, labelKey: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(L10n.text(labelKey))
        }
    }

    private func chartColumn(titleKey: String, pair: NutritionMacroRatioPair) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                bar(height: barHeight(pair.currentPercent), color: Color(uiColor: .systemGreen))
                bar(height: barHeight(pair.targetPercent), color: Color(uiColor: .systemGray3))
            }
            .frame(height: 100, alignment: .bottom)

            Text("\(Int(pair.currentPercent.rounded()))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(L10n.text(titleKey))
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func bar(height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: 18, height: Swift.max(8, height))
    }

    private func barHeight(_ percent: Double) -> CGFloat {
        CGFloat(Swift.min(Swift.max(percent, 0), 100) / 100) * 90
    }
}

struct NutritionMealSegmentedPicker: View {
    @Binding var selection: NutritionMealType

    var body: some View {
        HStack(spacing: 8) {
            ForEach(NutritionMealType.allCases, id: \.self) { mealType in
                Button {
                    selection = mealType
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mealType.iconName)
                            .font(.caption)
                        Text(L10n.text(mealType.localizationKey))
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selection == mealType ? Color(uiColor: .systemGreen).opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                selection == mealType ? Color(uiColor: .systemGreen) : Color(uiColor: .separator),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension NutritionMealType {
    var iconName: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "leaf.fill"
        }
    }
}

#Preview("Nutrition Cards") {
    ScrollView {
        VStack(spacing: 16) {
            NutritionOverviewGridCard(
                data: NutritionOverviewGridData(
                    energyKcal: 615,
                    proteinGrams: 17,
                    carbohydrateGrams: 84.7,
                    fatGrams: 28.2
                )
            )
            NutritionMacroProgressCard(
                titleKey: "nutrition.detail.macro_intake.title",
                data: NutritionMacroProgressCardData(
                    energy: NutritionMacroProgress(current: 757, target: 2118, unit: "kcal"),
                    carbohydrate: NutritionMacroProgress(current: 121, target: 258, unit: "g"),
                    protein: NutritionMacroProgress(current: 19, target: 103, unit: "g"),
                    fat: NutritionMacroProgress(current: 29, target: 68, unit: "g")
                )
            )
        }
        .padding()
    }
}
