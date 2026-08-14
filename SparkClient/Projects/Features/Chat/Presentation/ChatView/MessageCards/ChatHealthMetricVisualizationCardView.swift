import SwiftUI

struct ChatStepVisualizationMessageCard: View {
    let model: ChatHealthStepModel

    private var sortedDays: [ChatHealthStepModel.Day] {
        model.days.sorted { $0.date < $1.date }
    }

    private var totalSteps: Double {
        model.days.reduce(0) { $0 + $1.totalSteps }
    }

    private var totalDistanceMeters: Double {
        model.days.reduce(0) { $0 + $1.totalDistanceMeters }
    }

    var body: some View {
        ChatHealthMetricCardContainer(
            title: L10n.text("chat.step.visualization.title", fallback: "Step Data"),
            subtitle: model.dateRangeText,
            systemImage: "figure.walk",
            tint: .green
        ) {
            ChatHealthMetricSummaryGrid(items: [
                .init(
                    title: L10n.text("health.tool.metric.steps", fallback: "Steps"),
                    value: formatWhole(totalSteps),
                    icon: "shoeprints.fill"
                ),
                .init(
                    title: L10n.text("health.tool.metric.distance", fallback: "Distance"),
                    value: formatDistance(totalDistanceMeters),
                    icon: "point.topleft.down.curvedto.point.bottomright.up"
                )
            ])

            if sortedDays.count == 1, let day = sortedDays.first {
                hourlySection(title: day.title, rows: day.hourly)
            } else if sortedDays.count >= 2, sortedDays.count <= 4 {
                dailyBarComparison
            } else if sortedDays.count > 4 {
                dailyColumnTrend
            }
        }
    }

    private func hourlySection(
        title: String,
        rows: [ChatHealthStepModel.HourlyValue]
    ) -> some View {
        let maxSteps = max(rows.map(\.steps).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(rows.prefix(12)) { row in
                    ChatHealthMetricBarRow(
                        label: row.hourText,
                        valueText: "\(formatWhole(row.steps)) \(L10n.text("health.tool.unit.steps", fallback: "steps"))",
                        fraction: row.steps / maxSteps,
                        tint: .green
                    )
                }
            }
            if rows.count > 12 {
                Text(L10n.format("chat.health_metric.more_hours_format", fallback: "%d more time periods", rows.count - 12))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var dailyBarComparison: some View {
        let maxSteps = max(sortedDays.map(\.totalSteps).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("chat.step.daily_comparison.title", fallback: "Daily step comparison"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(sortedDays) { day in
                    ChatHealthDailyBarRow(
                        label: day.title,
                        primaryText: "\(formatWhole(day.totalSteps)) \(L10n.text("health.tool.unit.steps", fallback: "steps"))",
                        secondaryText: formatDistance(day.totalDistanceMeters),
                        fraction: day.totalSteps / maxSteps,
                        tint: .green
                    )
                }
            }
        }
    }

    private var dailyColumnTrend: some View {
        ChatHealthDailyColumnChart(
            title: L10n.text("chat.step.daily_trend.title", fallback: "Daily step trend"),
            items: sortedDays.map {
                ChatHealthDailyChartItem(
                    label: $0.date,
                    value: $0.totalSteps,
                    valueText: "\(formatWhole($0.totalSteps)) \(L10n.text("health.tool.unit.steps", fallback: "steps"))",
                    secondaryText: formatDistance($0.totalDistanceMeters)
                )
            },
            tint: .green
        )
    }
}

struct ChatEnergyVisualizationMessageCard: View {
    let model: ChatHealthEnergyModel

    private var sortedDays: [ChatHealthEnergyModel.Day] {
        model.days.sorted { $0.date < $1.date }
    }

    private var basalEnergy: Double {
        model.days.reduce(0) { $0 + $1.basalEnergyKcal }
    }

    private var activeEnergy: Double {
        model.days.reduce(0) { $0 + $1.activeEnergyKcal }
    }

    var body: some View {
        ChatHealthMetricCardContainer(
            title: L10n.text("chat.energy.visualization.title", fallback: "Energy Data"),
            subtitle: model.dateRangeText,
            systemImage: "flame.fill",
            tint: .orange
        ) {
            ChatHealthMetricSummaryGrid(items: [
                .init(
                    title: L10n.text("health.tool.metric.active_energy", fallback: "Active Energy"),
                    value: formatEnergy(activeEnergy),
                    icon: "bolt.fill"
                ),
                .init(
                    title: L10n.text("health.tool.metric.basal_energy", fallback: "Basal Energy"),
                    value: formatEnergy(basalEnergy),
                    icon: "circle.hexagongrid.fill"
                )
            ])

            if sortedDays.count == 1, let day = sortedDays.first {
                hourlySection(title: day.title, rows: day.hourly)
            } else if sortedDays.count >= 2, sortedDays.count <= 4 {
                dailyBarComparison
            } else if sortedDays.count > 4 {
                dailyColumnTrend
            }
        }
    }

    private func hourlySection(
        title: String,
        rows: [ChatHealthEnergyModel.HourlyValue]
    ) -> some View {
        let maxEnergy = max(rows.map { $0.activeEnergyKcal + $0.basalEnergyKcal }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(rows.prefix(12)) { row in
                    ChatHealthMetricBarRow(
                        label: row.hourText,
                        valueText: "\(formatEnergy(row.activeEnergyKcal)) / \(formatEnergy(row.basalEnergyKcal))",
                        fraction: (row.activeEnergyKcal + row.basalEnergyKcal) / maxEnergy,
                        tint: .orange
                    )
                }
            }
            if rows.count > 12 {
                Text(L10n.format("chat.health_metric.more_hours_format", fallback: "%d more time periods", rows.count - 12))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var dailyBarComparison: some View {
        let maxEnergy = max(sortedDays.map { $0.activeEnergyKcal + $0.basalEnergyKcal }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("chat.energy.daily_comparison.title", fallback: "Daily energy comparison"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(sortedDays) { day in
                    let total = day.activeEnergyKcal + day.basalEnergyKcal
                    ChatHealthDailyBarRow(
                        label: day.title,
                        primaryText: formatEnergy(total),
                        secondaryText: "\(L10n.text("health.tool.metric.active_energy", fallback: "Active")) \(formatEnergy(day.activeEnergyKcal))",
                        fraction: total / maxEnergy,
                        tint: .orange
                    )
                }
            }
        }
    }

    private var dailyColumnTrend: some View {
        ChatHealthDailyColumnChart(
            title: L10n.text("chat.energy.daily_trend.title", fallback: "Daily energy trend"),
            items: sortedDays.map {
                let total = $0.activeEnergyKcal + $0.basalEnergyKcal
                return ChatHealthDailyChartItem(
                    label: $0.date,
                    value: total,
                    valueText: formatEnergy(total),
                    secondaryText: "\(L10n.text("health.tool.metric.active_energy", fallback: "Active")) \(formatEnergy($0.activeEnergyKcal))"
                )
            },
            tint: .orange
        )
    }
}

struct ChatNutritionReadVisualizationMessageCard: View {
    let model: ChatHealthNutritionReadModel

    private var totals: ChatHealthNutritionReadModel.Segment {
        model.segments.reduce(
            ChatHealthNutritionReadModel.Segment(
                label: L10n.text("chat.nutrition_read.total", fallback: "Total"),
                proteinGrams: 0,
                carbohydratesGrams: 0,
                fatGrams: 0,
                energyKilocalories: 0
            )
        ) { partial, segment in
            ChatHealthNutritionReadModel.Segment(
                label: partial.label,
                proteinGrams: partial.proteinGrams + segment.proteinGrams,
                carbohydratesGrams: partial.carbohydratesGrams + segment.carbohydratesGrams,
                fatGrams: partial.fatGrams + segment.fatGrams,
                energyKilocalories: partial.energyKilocalories + segment.energyKilocalories
            )
        }
    }

    var body: some View {
        ChatHealthMetricCardContainer(
            title: L10n.text("chat.nutrition_read.visualization.title", fallback: "Nutrition Data"),
            subtitle: model.dateRangeText,
            systemImage: "fork.knife.circle.fill",
            tint: .mint
        ) {
            ChatHealthMetricSummaryGrid(items: [
                .init(
                    title: L10n.text("chat.nutrition_card.energy", fallback: "Energy"),
                    value: formatEnergy(totals.energyKilocalories),
                    icon: "flame.fill"
                ),
                .init(
                    title: L10n.text("chat.nutrition_card.protein", fallback: "Protein"),
                    value: formatGram(totals.proteinGrams),
                    icon: "fish.fill"
                ),
                .init(
                    title: L10n.text("chat.nutrition_card.carbohydrates", fallback: "Carbs"),
                    value: formatGram(totals.carbohydratesGrams),
                    icon: "popcorn.fill"
                ),
                .init(
                    title: L10n.text("chat.nutrition_card.fat", fallback: "Fat"),
                    value: formatGram(totals.fatGrams),
                    icon: "drop.fill"
                )
            ])

            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.segments) { segment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(segment.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ChatHealthMetricSummaryGrid(items: [
                            .init(title: L10n.text("chat.nutrition_card.energy", fallback: "Energy"), value: formatEnergy(segment.energyKilocalories), icon: "flame"),
                            .init(title: L10n.text("chat.nutrition_card.protein", fallback: "Protein"), value: formatGram(segment.proteinGrams), icon: "fish"),
                            .init(title: L10n.text("chat.nutrition_card.carbohydrates", fallback: "Carbs"), value: formatGram(segment.carbohydratesGrams), icon: "leaf"),
                            .init(title: L10n.text("chat.nutrition_card.fat", fallback: "Fat"), value: formatGram(segment.fatGrams), icon: "drop")
                        ])
                    }
                }
            }

            Text(L10n.text(
                "chat.nutrition_read.read_only_hint",
                fallback: "This card shows nutrition data read from the Health app. Only AI-generated nutrition cards can be written to Apple Health."
            ))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ChatHealthMetricCardContainer<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            content

            HealthKitDataSourceAttribution()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ChatHealthMetricSummaryGrid: View {
    let items: [Item]

    struct Item: Identifiable {
        var id: String { "\(title)-\(value)-\(icon)" }
        let title: String
        let value: String
        let icon: String
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(item.value)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct ChatHealthMetricBarRow: View {
    let label: String
    let valueText: String
    let fraction: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(tint.opacity(0.72))
                        .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 8)
            Text(valueText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 92, alignment: .trailing)
        }
    }
}

private struct ChatHealthDailyBarRow: View {
    let label: String
    let primaryText: String
    let secondaryText: String
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(primaryText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(secondaryText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(tint.opacity(0.72))
                        .frame(width: max(5, proxy.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 9)
        }
        .padding(8)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ChatHealthDailyChartItem: Identifiable {
    var id: String { "\(label)-\(valueText)-\(secondaryText)" }
    let label: String
    let value: Double
    let valueText: String
    let secondaryText: String
}

private struct ChatHealthDailyColumnChart: View {
    let title: String
    let items: [ChatHealthDailyChartItem]
    let tint: Color

    private var maxValue: Double {
        max(items.map(\.value).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(items) { item in
                        VStack(spacing: 6) {
                            Text(item.valueText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .frame(width: 54)
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(tint.opacity(0.72))
                                    .frame(height: max(6, 128 * min(max(item.value / maxValue, 0), 1)))
                            }
                            .frame(width: 28, height: 128)
                            Text(item.label)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: 54)
                            Text(item.secondaryText)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .frame(width: 54)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

private func formatWhole(_ value: Double) -> String {
    String(format: "%.0f", value)
}

private func formatDistance(_ meters: Double) -> String {
    if meters >= 1000 {
        return String(format: "%.2f km", meters / 1000)
    }
    return String(format: "%.0f m", meters)
}

private func formatEnergy(_ value: Double) -> String {
    String(format: "%.0f kcal", value)
}

private func formatGram(_ value: Double) -> String {
    String(format: "%.1f g", value)
}
