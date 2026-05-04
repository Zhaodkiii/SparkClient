import Foundation

struct ChatHealthWorkoutModel: Codable, Equatable, Sendable {
    static let schema = "health_workout_v1"

    var schemaVersion: String = schema
    var generatedAt: Int64
    var workouts: [WorkoutSession]
    var notes: [String]

    struct WorkoutSession: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var activityTypeKey: String
        var activityTypeName: String
        var start: Int64
        var end: Int64
        var startText: String?
        var endText: String?
        var elapsedSeconds: Int64
        var trainingSeconds: Int64?
        var pausedSeconds: Int64?
        var distanceMeters: Double?
        var activeEnergyKcal: Double?
        var totalEnergyKcal: Double?
        var elevationAscendedMeters: Double?
        var averageSpeedMps: Double?
        var averageHeartRateBpm: Double?
        var averagePowerW: Double?
        var averageCadence: Double?
        var averagePaceMinPerKm: Double?
        var poolLengthMeters: Double?
        var swimmingLengthCount: Int?
        var heartRateSamples: [HeartRatePoint]
        var events: [WorkoutEvent]
        var route: [RoutePoint]
    }

    struct HeartRatePoint: Codable, Equatable, Identifiable, Sendable {
        var id: Int64 { timestamp }
        var timestamp: Int64
        var bpm: Double
    }

    struct HeartRateBin: Equatable, Sendable {
        let min: Double
        let max: Double
        let timestamp: Int64
        let isEmpty: Bool
    }

    struct WorkoutEvent: Codable, Equatable, Identifiable, Sendable {
        var id: String { "\(type.rawValue)_\(dateIntervalSince1970)" }
        var type: EventType
        var dateIntervalSince1970: Int64

        enum EventType: String, Codable, Equatable, Sendable {
            case pause
            case resume
            case lap
            case marker
            case segment
            case other
        }
    }

    struct RoutePoint: Codable, Equatable, Sendable {
        var lat: Double
        var lon: Double
        var altitudeM: Double?
        var timestamp: Int64
    }
}

extension ChatHealthWorkoutModel {
    static func binHeartRates(samples: [HeartRatePoint], maxBins: Int) -> [HeartRateBin] {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        guard sorted.isEmpty == false, maxBins > 0 else { return [] }

        let start = sorted[0].timestamp
        let end = sorted[sorted.count - 1].timestamp
        let duration = max(1, end - start)
        let step = Double(duration) / Double(maxBins)

        var bins: [HeartRateBin] = []
        bins.reserveCapacity(maxBins)

        var index = 0
        for binIndex in 0..<maxBins {
            let binStart = start + Int64(Double(binIndex) * step)
            let binEnd = start + Int64(Double(binIndex + 1) * step)

            while index < sorted.count, sorted[index].timestamp < binStart {
                index += 1
            }

            var cursor = index
            var minBpm = Double.greatestFiniteMagnitude
            var maxBpm = -Double.greatestFiniteMagnitude
            while cursor < sorted.count, sorted[cursor].timestamp < binEnd {
                let bpm = sorted[cursor].bpm
                minBpm = min(minBpm, bpm)
                maxBpm = max(maxBpm, bpm)
                cursor += 1
            }

            if maxBpm >= minBpm {
                bins.append(HeartRateBin(min: minBpm, max: maxBpm, timestamp: binStart, isEmpty: false))
            } else {
                bins.append(HeartRateBin(min: 0, max: 0, timestamp: binStart, isEmpty: true))
            }
            index = cursor
        }

        return bins
    }

    func toReadableText() -> String {
        let sorted = workouts.sorted { $0.start < $1.start }
        guard sorted.isEmpty == false else {
            return L10n.text("health.tool.error.no_workouts", fallback: "No matching workout records found.")
        }

        let totalDurationMinutes = sorted.reduce(0.0) { $0 + Double($1.elapsedSeconds) / 60 }
        let totalDistanceMeters = sorted.compactMap(\.distanceMeters).reduce(0, +)
        let totalEnergy = sorted.compactMap(\.activeEnergyKcal).reduce(0, +)

        var lines: [String] = []
        lines.append(L10n.text("health.tool.report.workouts.title", fallback: "Workout records"))
        lines.append(
            String(
                format: L10n.text(
                    "chat.workout.readable.summary_format",
                    fallback: "%d sessions, total duration %@, total distance %@, active energy %.0f kcal"
                ),
                locale: .current,
                sorted.count,
                Self.formatDurationMinutes(totalDurationMinutes),
                Self.formatDistanceMeters(totalDistanceMeters),
                totalEnergy
            )
        )

        if notes.isEmpty == false {
            lines.append(contentsOf: notes)
        }

        for workout in sorted.prefix(20) {
            var metrics = [
                Self.formatDurationMinutes(Double(workout.elapsedSeconds) / 60)
            ]
            if let distance = workout.distanceMeters, distance > 0 {
                metrics.append(Self.formatDistanceMeters(distance))
            }
            if let energy = workout.activeEnergyKcal, energy > 0 {
                metrics.append(String(format: "%.0f kcal", energy))
            }
            if let heartRate = workout.averageHeartRateBpm, heartRate > 0 {
                metrics.append(String(format: "%.0f bpm", heartRate))
            }
            lines.append("- \(workout.startText ?? "") \(workout.activityTypeName): \(metrics.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    static func formatDurationMinutes(_ minutes: Double) -> String {
        let hours = Int(minutes / 60)
        let mins = Int(minutes.truncatingRemainder(dividingBy: 60))
        if hours > 0 {
            return String(format: L10n.text("health.tool.unit.duration.hours_minutes", fallback: "%dh %dm"), locale: .current, hours, mins)
        }
        return String(format: L10n.text("health.tool.unit.duration.minutes", fallback: "%dm"), locale: .current, mins)
    }

    static func formatDistanceMeters(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: L10n.text("health.tool.unit.kilometers.precision", fallback: "%.2f km"), locale: .current, meters / 1000)
        }
        return String(format: L10n.text("health.tool.unit.meters", fallback: "%d m"), locale: .current, Int(meters.rounded()))
    }
}
