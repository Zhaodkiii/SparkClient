import Foundation

nonisolated struct ChatHealthStepModel: Codable, Equatable, Sendable {
    var dateRangeText: String
    var days: [Day]

    nonisolated struct Day: Identifiable, Codable, Equatable, Sendable {
        var id: String { date }
        var date: String
        var title: String
        var totalSteps: Double
        var totalDistanceMeters: Double
        var hourly: [HourlyValue]
    }

    nonisolated struct HourlyValue: Identifiable, Codable, Equatable, Sendable {
        var id: String { hourText }
        var hourText: String
        var steps: Double
        var distanceMeters: Double
    }

    nonisolated func toReadableText() -> String {
        var lines = ["\(L10n.text("health.tool.report.steps_distance.title", fallback: "Steps and Distance")) \(dateRangeText):"]
        for day in days {
            lines.append("\n*\(day.title)*")
            for row in day.hourly {
                lines.append("  - \(row.hourText): \(L10n.text("health.tool.metric.steps", fallback: "Steps")) \(formatWhole(row.steps)), \(L10n.text("health.tool.metric.distance", fallback: "Distance")) \(formatDistance(row.distanceMeters))")
            }
            lines.append("  - \(L10n.text("health.tool.report.daily_total", fallback: "Daily total")): \(formatWhole(day.totalSteps)) \(L10n.text("health.tool.unit.steps", fallback: "steps")), \(formatDistance(day.totalDistanceMeters))")
        }
        let totalSteps = days.reduce(0) { $0 + $1.totalSteps }
        let totalDistance = days.reduce(0) { $0 + $1.totalDistanceMeters }
        lines.append("\n\(L10n.text("health.tool.report.steps_distance.total", fallback: "Total steps and distance")): \(formatWhole(totalSteps)) \(L10n.text("health.tool.unit.steps", fallback: "steps")), \(formatDistance(totalDistance))")
        return lines.joined(separator: "\n")
    }
}

nonisolated struct ChatHealthEnergyModel: Codable, Equatable, Sendable {
    var dateRangeText: String
    var days: [Day]

    nonisolated struct Day: Identifiable, Codable, Equatable, Sendable {
        var id: String { date }
        var date: String
        var title: String
        var basalEnergyKcal: Double
        var activeEnergyKcal: Double
        var hourly: [HourlyValue]
    }

    nonisolated struct HourlyValue: Identifiable, Codable, Equatable, Sendable {
        var id: String { hourText }
        var hourText: String
        var basalEnergyKcal: Double
        var activeEnergyKcal: Double
    }

    nonisolated func toReadableText() -> String {
        var lines = ["\(L10n.text("health.tool.report.energy.title", fallback: "Energy")) \(dateRangeText):"]
        for day in days {
            lines.append("\n*\(day.title)*")
            for row in day.hourly {
                lines.append("  - \(row.hourText): \(L10n.text("health.tool.metric.basal_energy", fallback: "Basal Energy")) \(formatEnergy(row.basalEnergyKcal)), \(L10n.text("health.tool.metric.active_energy", fallback: "Active Energy")) \(formatEnergy(row.activeEnergyKcal))")
            }
            lines.append("  - \(L10n.text("health.tool.report.daily_total", fallback: "Daily total")): \(formatEnergy(day.basalEnergyKcal)), \(formatEnergy(day.activeEnergyKcal))")
        }
        let basal = days.reduce(0) { $0 + $1.basalEnergyKcal }
        let active = days.reduce(0) { $0 + $1.activeEnergyKcal }
        lines.append("\n\(L10n.text("health.tool.report.energy.total", fallback: "Total energy")): \(formatEnergy(basal)), \(formatEnergy(active))")
        return lines.joined(separator: "\n")
    }
}

nonisolated struct ChatHealthNutritionReadModel: Codable, Equatable, Sendable {
    var dateRangeText: String
    var segments: [Segment]

    nonisolated struct Segment: Identifiable, Codable, Equatable, Sendable {
        var id: String { label }
        var label: String
        var proteinGrams: Double
        var carbohydratesGrams: Double
        var fatGrams: Double
        var energyKilocalories: Double
    }

    nonisolated func toReadableText() -> String {
        var lines = ["\(L10n.text("health.tool.report.nutrition.title", fallback: "Nutrition Intake")) \(dateRangeText):"]
        for segment in segments {
            lines.append("\n【\(segment.label)】")
            if segment.proteinGrams > 0 {
                lines.append("- \(L10n.text("health.tool.metric.protein", fallback: "Protein")): \(formatGram(segment.proteinGrams))")
            }
            if segment.carbohydratesGrams > 0 {
                lines.append("- \(L10n.text("health.tool.metric.carbs", fallback: "Carbs")): \(formatGram(segment.carbohydratesGrams))")
            }
            if segment.fatGrams > 0 {
                lines.append("- \(L10n.text("health.tool.metric.fat", fallback: "Fat")): \(formatGram(segment.fatGrams))")
            }
            if segment.energyKilocalories > 0 {
                lines.append("- \(L10n.text("health.tool.metric.dietary_energy", fallback: "Dietary Energy")): \(formatEnergy(segment.energyKilocalories))")
            }
        }
        return lines.joined(separator: "\n")
    }
}

nonisolated private func formatWhole(_ value: Double) -> String {
    String(format: "%.0f", value)
}

nonisolated private func formatDistance(_ meters: Double) -> String {
    if meters >= 1000 {
        return String(format: "%.2f km", meters / 1000)
    }
    return String(format: "%.0f m", meters)
}

nonisolated private func formatEnergy(_ value: Double) -> String {
    String(format: "%.1f kcal", value)
}

nonisolated private func formatGram(_ value: Double) -> String {
    String(format: "%.1f g", value)
}
