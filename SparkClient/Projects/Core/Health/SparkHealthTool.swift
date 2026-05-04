import CoreLocation
import Foundation
import HealthKit

struct SparkNutritionCard: Equatable, Codable, Sendable {
    var date: Date
    var proteinGrams: Double?
    var carbohydratesGrams: Double?
    var fatGrams: Double?
    var energyKilocalories: Double?
    var isWritten: Bool
}

struct SparkHealthToolError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// HealthKit-backed health data tool used by AI tool calls.
final class SparkHealthTool: @unchecked Sendable {
    static let shared = SparkHealthTool()

    private let healthStore = HKHealthStore()
    private let logger: Logger

    init(logger: Logger = ConsoleLogger()) {
        self.logger = logger
    }

    func fetchStepDetails(from startDate: Date, to endDate: Date) async -> String {
        await fetchHourlyQuantityPair(
            startDate: startDate,
            endDate: endDate,
            left: QuantityMetric(
                identifier: .stepCount,
                unit: .count(),
                labelKey: "health.tool.metric.steps",
                formatter: { value in
                    SparkHealthTool.formatIntegerUnit(value, key: "health.tool.unit.steps")
                }
            ),
            right: QuantityMetric(
                identifier: .distanceWalkingRunning,
                unit: .meter(),
                labelKey: "health.tool.metric.distance",
                formatter: { value in
                    SparkHealthTool.formatDistanceMeters(value)
                }
            ),
            titleKey: "health.tool.report.steps_distance.title",
            totalKey: "health.tool.report.steps_distance.total"
        )
    }

    func fetchEnergyDetails(from startDate: Date, to endDate: Date) async -> String {
        await fetchHourlyQuantityPair(
            startDate: startDate,
            endDate: endDate,
            left: QuantityMetric(
                identifier: .basalEnergyBurned,
                unit: .kilocalorie(),
                labelKey: "health.tool.metric.basal_energy",
                formatter: { value in
                    SparkHealthTool.formatDoubleUnit(value, key: "health.tool.unit.kcal.precision")
                }
            ),
            right: QuantityMetric(
                identifier: .activeEnergyBurned,
                unit: .kilocalorie(),
                labelKey: "health.tool.metric.active_energy",
                formatter: { value in
                    SparkHealthTool.formatDoubleUnit(value, key: "health.tool.unit.kcal.precision")
                }
            ),
            titleKey: "health.tool.report.energy.title",
            totalKey: "health.tool.report.energy.total"
        )
    }

    func fetchNutritionDetails(from startDate: Date, to endDate: Date) async -> String {
        let calendar = Calendar.current

        guard validateDateRange(startDate: startDate, endDate: endDate) else {
            return Self.text("health.tool.error.invalid_date_range.detailed")
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            return Self.text("health.tool.error.healthkit_unavailable")
        }

        guard
            let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
            let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
            let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal),
            let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)
        else {
            return Self.text("health.tool.error.nutrition_types_unavailable")
        }

        do {
            try await requestAuthorization()
            let predicateEnd = inclusivePredicateEnd(for: endDate)

            async let protein = quantitySamples(type: proteinType, unit: .gram(), start: startDate, end: predicateEnd)
            async let carbs = quantitySamples(type: carbType, unit: .gram(), start: startDate, end: predicateEnd)
            async let fat = quantitySamples(type: fatType, unit: .gram(), start: startDate, end: predicateEnd)
            async let energy = quantitySamples(type: energyType, unit: .kilocalorie(), start: startDate, end: predicateEnd)

            let (proteinValues, carbValues, fatValues, energyValues) = try await (protein, carbs, fat, energy)
            let rows = [
                NutritionSeries(labelKey: "health.tool.metric.protein", unit: "g", values: proteinValues),
                NutritionSeries(labelKey: "health.tool.metric.carbs", unit: "g", values: carbValues),
                NutritionSeries(labelKey: "health.tool.metric.fat", unit: "g", values: fatValues),
                NutritionSeries(labelKey: "health.tool.metric.dietary_energy", unit: "kcal", values: energyValues)
            ]

            let segments = Self.mealSegments()
            var output = "\(Self.text("health.tool.report.nutrition.title")) \(Self.dateRangeText(startDate, endDate)):\n"
            var hasData = false

            for segment in segments {
                var segmentLines: [String] = []
                for row in rows {
                    let total = row.values
                        .filter { segment.contains(calendar.component(.hour, from: $0.date)) }
                        .map(\.value)
                        .reduce(0, +)
                    guard total > 0 else { continue }
                    hasData = true
                    let label = Self.text(row.labelKey)
                    segmentLines.append("- \(label): \(String(format: "%.1f", total))\(row.unit)")
                }
                if segmentLines.isEmpty == false {
                    output += "\n【\(segment.label)】\n\(segmentLines.joined(separator: "\n"))\n"
                }
            }

            return hasData ? output.trimmingCharacters(in: .whitespacesAndNewlines) : Self.text("health.tool.error.no_nutrition")
        } catch {
            logger.error("HealthKit nutrition query failed: \(error.localizedDescription)", module: .aiConfig)
            return Self.format("health.tool.error.nutrition_query_failed", error.localizedDescription)
        }
    }

    func fetchSleepDetails(from startDate: Date, to endDate: Date) async throws -> ChatHealthSleepModel {
        let calendar = Calendar.current

        guard validateDateRange(startDate: startDate, endDate: endDate) else {
            throw SparkHealthToolError(message: Self.text("health.tool.error.invalid_date_range"))
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            throw SparkHealthToolError(message: Self.text("health.tool.error.healthkit_unavailable"))
        }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw SparkHealthToolError(message: Self.text("health.tool.error.sleep_type_unavailable"))
        }

        try await requestAuthorization()

        let bedtimeHour = 20
        let bedtimeMinute = 0
        let prevDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: startDate)) ?? startDate
        let predicateStart = calendar.date(bySettingHour: bedtimeHour, minute: bedtimeMinute, second: 0, of: prevDay) ?? prevDay
        let predicateEnd = inclusivePredicateEnd(for: endDate)
        let samples = try await categorySamples(type: sleepType, start: predicateStart, end: predicateEnd)

        let acceptedStages = Self.acceptedSleepStageRawValues()
        let filteredSamples = samples.filter { acceptedStages.contains($0.value) }
        guard filteredSamples.isEmpty == false else {
            throw SparkHealthToolError(message: Self.text("health.tool.error.no_sleep"))
        }

        let isoDayFormatter = Self.dayFormatter(calendar: calendar)
        let clockFormatter = Self.clockFormatter(calendar: calendar)

        func sleepDayAnchor(for date: Date) -> Date {
            let todayStart = calendar.startOfDay(for: date)
            guard let bedtimeToday = calendar.date(bySettingHour: bedtimeHour, minute: bedtimeMinute, second: 0, of: todayStart) else {
                return todayStart
            }
            return date < bedtimeToday
                ? (calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart)
                : todayStart
        }

        var grouped: [Date: [HKCategorySample]] = [:]
        for sample in filteredSamples {
            grouped[sleepDayAnchor(for: sample.startDate), default: []].append(sample)
        }

        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let days = grouped.keys
            .filter { $0 >= startDay && $0 <= endDay }
            .sorted()
            .compactMap { day -> ChatHealthSleepModel.Day? in
                let daySamples = (grouped[day] ?? []).sorted { $0.startDate < $1.startDate }
                guard let first = daySamples.first, let last = daySamples.last else { return nil }
                let spanStart = Int64(first.startDate.timeIntervalSince1970)
                let spanEnd = Int64(last.endDate.timeIntervalSince1970)
                let spanSeconds = max(1, Double(spanEnd - spanStart))

                var stageMinutes: [ChatHealthSleepModel.Stage: Int] = [:]
                let segments = daySamples.map { sample -> ChatHealthSleepModel.Segment in
                    let stage = Self.chatStage(fromRawValue: sample.value)
                    let start = Int64(sample.startDate.timeIntervalSince1970)
                    let end = Int64(sample.endDate.timeIntervalSince1970)
                    let minutes = Int((sample.endDate.timeIntervalSince(sample.startDate) / 60).rounded())
                    stageMinutes[stage, default: 0] += max(0, minutes)

                    return ChatHealthSleepModel.Segment(
                        stage: stage,
                        start: start,
                        end: end,
                        startPercent: max(0, Double(start - spanStart) / spanSeconds * 100),
                        widthPercent: max(0.01, Double(end - start) / spanSeconds * 100),
                        startText: clockFormatter.string(from: sample.startDate),
                        endText: clockFormatter.string(from: sample.endDate)
                    )
                }

                let awake = stageMinutes[.awake] ?? 0
                let totalSleep = max(0, stageMinutes.reduce(0) { partial, item in
                    item.key == .awake ? partial : partial + item.value
                })

                return ChatHealthSleepModel.Day(
                    date: isoDayFormatter.string(from: day),
                    summary: ChatHealthSleepModel.Summary(
                        totalSleepMinutes: totalSleep,
                        start: spanStart,
                        end: spanEnd,
                        startText: clockFormatter.string(from: first.startDate),
                        endText: clockFormatter.string(from: last.endDate)
                    ),
                    timeline: segments,
                    stages: ChatHealthSleepModel.StageBreakdown(
                        deep: stageMinutes[.deep] ?? 0,
                        core: stageMinutes[.core] ?? 0,
                        rem: stageMinutes[.rem] ?? 0,
                        awake: awake,
                        unspecified: stageMinutes[.unspecified] ?? 0
                    )
                )
            }

        guard days.isEmpty == false else {
            throw SparkHealthToolError(message: Self.text("health.tool.error.no_sleep_range"))
        }

        return ChatHealthSleepModel(generatedAt: Int64(Date().timeIntervalSince1970), days: days)
    }

    func fetchWorkoutDetails(from startDate: Date, to endDate: Date, types: [String], maxItems: Int) async throws -> ChatHealthWorkoutModel {
        guard validateDateRange(startDate: startDate, endDate: endDate) else {
            throw SparkHealthToolError(message: Self.text("health.tool.error.invalid_date_range"))
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            throw SparkHealthToolError(message: Self.text("health.tool.error.healthkit_unavailable"))
        }

        try await requestAuthorization()

        let activityTypes = types.compactMap(Self.parseWorkoutActivityType)
        let unrecognized = types.filter { Self.parseWorkoutActivityType($0) == nil }
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: inclusivePredicateEnd(for: endDate))
        let predicate: NSPredicate
        if activityTypes.isEmpty {
            predicate = datePredicate
        } else {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                datePredicate,
                NSCompoundPredicate(orPredicateWithSubpredicates: activityTypes.map { HKQuery.predicateForWorkouts(with: $0) })
            ])
        }

        let workouts = try await workoutSamples(predicate: predicate, limit: max(1, min(maxItems, 100)))
        var notes: [String] = []
        if unrecognized.isEmpty == false {
            notes.append(Self.format("health.tool.warning.unrecognized_activity_types", unrecognized.joined(separator: ", ")))
        }

        var sessions: [ChatHealthWorkoutModel.WorkoutSession] = []
        for workout in workouts {
            if let session = await enrichWorkoutSession(workout) {
                sessions.append(session)
            }
        }

        if sessions.isEmpty {
            notes.append(Self.text("health.tool.error.no_workouts"))
        }

        return ChatHealthWorkoutModel(
            generatedAt: Int64(Date().timeIntervalSince1970),
            workouts: sessions,
            notes: notes
        )
    }

    func makeNutritionData(protein: Double?, carbohydrates: Double?, fat: Double?, energy: Double?, date: Date = Date()) -> SparkNutritionCard {
        SparkNutritionCard(
            date: date,
            proteinGrams: protein,
            carbohydratesGrams: carbohydrates,
            fatGrams: fat,
            energyKilocalories: energy,
            isWritten: false
        )
    }

    func writeNutritionData(_ data: SparkNutritionCard) async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw SparkHealthToolError(message: Self.text("health.tool.error.health_data_unavailable_device"))
        }
        guard
            let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
            let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
            let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal),
            let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)
        else {
            throw SparkHealthToolError(message: Self.text("health.tool.error.dietary_types_unavailable"))
        }

        try await requestAuthorization(readTypes: [proteinType, carbType, fatType, energyType], writeTypes: [proteinType, carbType, fatType, energyType])

        var samples: [HKQuantitySample] = []
        if let value = data.proteinGrams {
            samples.append(HKQuantitySample(type: proteinType, quantity: HKQuantity(unit: .gram(), doubleValue: value), start: data.date, end: data.date))
        }
        if let value = data.carbohydratesGrams {
            samples.append(HKQuantitySample(type: carbType, quantity: HKQuantity(unit: .gram(), doubleValue: value), start: data.date, end: data.date))
        }
        if let value = data.fatGrams {
            samples.append(HKQuantitySample(type: fatType, quantity: HKQuantity(unit: .gram(), doubleValue: value), start: data.date, end: data.date))
        }
        if let value = data.energyKilocalories {
            samples.append(HKQuantitySample(type: energyType, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: value), start: data.date, end: data.date))
        }
        guard samples.isEmpty == false else { return true }

        return try await withCheckedThrowingContinuation { continuation in
            healthStore.save(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    private func fetchHourlyQuantityPair(
        startDate: Date,
        endDate: Date,
        left: QuantityMetric,
        right: QuantityMetric,
        titleKey: String,
        totalKey: String
    ) async -> String {
        let calendar = Calendar.current

        guard validateDateRange(startDate: startDate, endDate: endDate) else {
            return Self.text("health.tool.error.invalid_date_range.detailed")
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            return Self.text("health.tool.error.healthkit_unavailable")
        }
        guard
            let leftType = HKQuantityType.quantityType(forIdentifier: left.identifier),
            let rightType = HKQuantityType.quantityType(forIdentifier: right.identifier)
        else {
            return Self.text("health.tool.error.quantity_types_unavailable")
        }

        do {
            try await requestAuthorization()
            let predicateEnd = inclusivePredicateEnd(for: endDate)
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: predicateEnd)
            let anchorDate = calendar.startOfDay(for: startDate)
            let interval: DateComponents = {
                var value = DateComponents()
                value.hour = 1
                return value
            }()

            async let leftStats = statisticsCollection(type: leftType, predicate: predicate, anchorDate: anchorDate, interval: interval)
            async let rightStats = statisticsCollection(type: rightType, predicate: predicate, anchorDate: anchorDate, interval: interval)
            let (leftCollection, rightCollection) = try await (leftStats, rightStats)

            let dayFormatter = Self.displayDayFormatter(calendar: calendar)
            let timeFormatter = Self.displayTimeFormatter(calendar: calendar)
            let strideEnd = calendar.date(byAdding: .hour, value: 23, to: calendar.startOfDay(for: endDate)) ?? endDate
            var output = "\(Self.text(titleKey)) \(Self.dateRangeText(startDate, endDate)):\n"
            var totalLeft = 0.0
            var totalRight = 0.0
            var hasData = false

            for day in Self.days(from: startDate, to: endDate, calendar: calendar) {
                var dayLines: [String] = []
                var dayLeft = 0.0
                var dayRight = 0.0
                let dayEnd = min(strideEnd, calendar.date(byAdding: .hour, value: 23, to: day) ?? day)
                var hour = day
                while hour <= dayEnd {
                    let leftValue = leftCollection.statistics(for: hour)?.sumQuantity()?.doubleValue(for: left.unit) ?? 0
                    let rightValue = rightCollection.statistics(for: hour)?.sumQuantity()?.doubleValue(for: right.unit) ?? 0
                    if leftValue > 0 || rightValue > 0 {
                        hasData = true
                        dayLeft += leftValue
                        dayRight += rightValue
                        dayLines.append("  - \(timeFormatter.string(from: hour)): \(Self.text(left.labelKey)) \(left.formatter(leftValue)), \(Self.text(right.labelKey)) \(right.formatter(rightValue))")
                    }
                    guard let nextHour = calendar.date(byAdding: .hour, value: 1, to: hour), nextHour > hour else { break }
                    hour = nextHour
                }
                if dayLines.isEmpty == false {
                    totalLeft += dayLeft
                    totalRight += dayRight
                    output += "\n*\(dayFormatter.string(from: day))*\n\(dayLines.joined(separator: "\n"))\n"
                    output += "  - \(Self.text("health.tool.report.daily_total")): \(left.formatter(dayLeft)), \(right.formatter(dayRight))\n"
                }
            }

            guard hasData else {
                return Self.text("health.tool.error.no_matching_health")
            }
            output += "\n\(Self.text(totalKey)): \(left.formatter(totalLeft)), \(right.formatter(totalRight))"
            return output
        } catch {
            logger.error("HealthKit quantity query failed: \(error.localizedDescription)", module: .aiConfig)
            return Self.format("health.tool.error.quantity_query_failed", error.localizedDescription)
        }
    }

    private func requestAuthorization() async throws {
        var readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!
        ]
        if #available(iOS 16.0, *) {
            if let runningSpeed = HKObjectType.quantityType(forIdentifier: .runningSpeed) {
                readTypes.insert(runningSpeed)
            }
        }
        try await requestAuthorization(readTypes: readTypes, writeTypes: [])
    }

    private func requestAuthorization(readTypes: Set<HKObjectType>, writeTypes: Set<HKSampleType>) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func statisticsCollection(
        type: HKQuantityType,
        predicate: NSPredicate,
        anchorDate: Date,
        interval: DateComponents
    ) async throws -> HKStatisticsCollection {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let stats {
                    continuation.resume(returning: stats)
                } else {
                    continuation.resume(throwing: SparkHealthToolError(message: Self.text("health.tool.error.no_statistics")))
                }
            }
            healthStore.execute(query)
        }
    }

    private func quantitySamples(type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async throws -> [NutritionValue] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    let values = (samples as? [HKQuantitySample] ?? []).map {
                        NutritionValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                    }
                    continuation.resume(returning: values)
                }
            }
            healthStore.execute(query)
        }
    }

    private func categorySamples(type: HKCategoryType, start: Date, end: Date) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKCategorySample] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func workoutSamples(predicate: NSPredicate, limit: Int) async throws -> [HKWorkout] {
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: limit, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKWorkout] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func averageHeartRate(from start: Date, to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try? await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
                }
            }
            healthStore.execute(query)
        }
    }

    private func enrichWorkoutSession(_ workout: HKWorkout) async -> ChatHealthWorkoutModel.WorkoutSession? {
        let start = Int64(workout.startDate.timeIntervalSince1970)
        let end = Int64(workout.endDate.timeIntervalSince1970)
        let distanceMeters = workout.totalDistance?.doubleValue(for: .meter())
        let activeEnergyKcal = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        let elapsedSeconds = max(0, Int64(workout.duration.rounded()))
        let averageHeartRate = await averageHeartRate(from: workout.startDate, to: workout.endDate)
        let heartRates = await heartRateSamples(from: workout.startDate, to: workout.endDate, maxPoints: 160)
        let route = await routePoints(for: workout, maxPoints: 220)
        let averageSpeed = distanceMeters.flatMap { distance -> Double? in
            guard workout.duration > 0, distance > 0 else { return nil }
            return distance / workout.duration
        }
        let averagePace = averageSpeed.flatMap { speed -> Double? in
            guard speed > 0 else { return nil }
            return 1000 / speed / 60
        }

        return ChatHealthWorkoutModel.WorkoutSession(
            id: workout.uuid.uuidString,
            activityTypeKey: Self.workoutActivityTypeKey(workout.workoutActivityType),
            activityTypeName: Self.workoutActivityDisplayName(workout.workoutActivityType),
            start: start,
            end: end,
            startText: Self.dateTimeText(workout.startDate),
            endText: Self.dateTimeText(workout.endDate),
            elapsedSeconds: elapsedSeconds,
            trainingSeconds: nil,
            pausedSeconds: nil,
            distanceMeters: distanceMeters,
            activeEnergyKcal: activeEnergyKcal,
            totalEnergyKcal: activeEnergyKcal,
            elevationAscendedMeters: nil,
            averageSpeedMps: averageSpeed,
            averageHeartRateBpm: averageHeartRate,
            averagePowerW: nil,
            averageCadence: nil,
            averagePaceMinPerKm: averagePace,
            poolLengthMeters: Self.poolLengthMeters(from: workout),
            swimmingLengthCount: nil,
            heartRateSamples: heartRates,
            events: Self.workoutEvents(workout.workoutEvents ?? []),
            route: route
        )
    }

    private func heartRateSamples(from start: Date, to end: Date, maxPoints: Int) async -> [ChatHealthWorkoutModel.HeartRatePoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let limit = max(1, maxPoints * 4)
        let samples: [HKQuantitySample] = (try? await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                }
            }
            healthStore.execute(query)
        }) ?? []

        let mapped = samples.map {
            ChatHealthWorkoutModel.HeartRatePoint(
                timestamp: Int64($0.startDate.timeIntervalSince1970),
                bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            )
        }
        return Self.downsample(mapped, maxPoints: maxPoints)
    }

    private func routePoints(for workout: HKWorkout, maxPoints: Int) async -> [ChatHealthWorkoutModel.RoutePoint] {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routes: [HKWorkoutRoute] = (try? await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: routeType, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
                }
            }
            healthStore.execute(query)
        }) ?? []
        guard let route = routes.first else { return [] }

        let locations: [CLLocation] = (try? await withCheckedThrowingContinuation { continuation in
            var collected: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                collected.append(contentsOf: locations ?? [])
                if done {
                    continuation.resume(returning: collected)
                }
            }
            healthStore.execute(query)
        }) ?? []

        let points = locations.map {
            ChatHealthWorkoutModel.RoutePoint(
                lat: $0.coordinate.latitude,
                lon: $0.coordinate.longitude,
                altitudeM: $0.verticalAccuracy >= 0 ? $0.altitude : nil,
                timestamp: Int64($0.timestamp.timeIntervalSince1970)
            )
        }
        return Self.downsample(points, maxPoints: maxPoints)
    }

    private func validateDateRange(startDate: Date, endDate: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        return startDay <= today && endDay <= today && startDay <= endDay
    }

    private func inclusivePredicateEnd(for endDate: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
    }

    private static func text(_ key: String) -> String {
        L10n.text(key)
    }

    private static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }

    private static func acceptedSleepStageRawValues() -> Set<Int> {
        var values: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleep.rawValue
        ]
        if #available(iOS 16.0, *) {
            values.formUnion([
                HKCategoryValueSleepAnalysis.awake.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            ])
        }
        return values
    }

    private static func chatStage(fromRawValue rawValue: Int) -> ChatHealthSleepModel.Stage {
        if #available(iOS 16.0, *) {
            switch rawValue {
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                return .awake
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                return .core
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                return .deep
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                return .rem
            case HKCategoryValueSleepAnalysis.asleep.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                return .unspecified
            default:
                return .unspecified
            }
        }
        return rawValue == HKCategoryValueSleepAnalysis.asleep.rawValue ? .unspecified : .awake
    }

    private static func workoutActivityTypeKey(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .hiking: return "hiking"
        case .badminton: return "badminton"
        case .swimming: return "swimming"
        case .yoga: return "yoga"
        case .functionalStrengthTraining: return "functional_strength"
        case .traditionalStrengthTraining: return "traditional_strength"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        case .crossTraining: return "cross_training"
        case .highIntensityIntervalTraining: return "hiit"
        case .cardioDance: return "dance"
        case .coreTraining: return "core_training"
        case .pilates: return "pilates"
        case .other: return "other"
        default: return "workout"
        }
    }

    private static func workoutEvents(_ events: [HKWorkoutEvent]) -> [ChatHealthWorkoutModel.WorkoutEvent] {
        events.map { event in
            let type: ChatHealthWorkoutModel.WorkoutEvent.EventType
            switch event.type {
            case .pause:
                type = .pause
            case .resume:
                type = .resume
            case .lap:
                type = .lap
            case .marker:
                type = .marker
            case .segment:
                type = .segment
            default:
                type = .other
            }
            return ChatHealthWorkoutModel.WorkoutEvent(
                type: type,
                dateIntervalSince1970: Int64(event.dateInterval.start.timeIntervalSince1970)
            )
        }
    }

    private static func poolLengthMeters(from workout: HKWorkout) -> Double? {
        guard let raw = workout.metadata?[HKMetadataKeyLapLength] else { return nil }
        if let quantity = raw as? HKQuantity {
            return quantity.doubleValue(for: .meter())
        }
        return raw as? Double
    }

    private static func downsample<T>(_ values: [T], maxPoints: Int) -> [T] {
        guard values.count > maxPoints, maxPoints > 0 else { return values }
        guard maxPoints > 1 else { return Array(values.prefix(1)) }
        let stride = Double(values.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { values[Int((Double($0) * stride).rounded())] }
    }

    private static func parseWorkoutActivityType(_ value: String) -> HKWorkoutActivityType? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "running", "run": return .running
        case "walking", "walk", "outdoor_walk": return .walking
        case "cycling", "cycle", "outdoor_cycle", "outdoor_cycling": return .cycling
        case "hiking", "hike": return .hiking
        case "badminton": return .badminton
        case "swimming", "swim": return .swimming
        case "yoga": return .yoga
        case "functional_strength", "strength": return .functionalStrengthTraining
        case "traditional_strength", "weights": return .traditionalStrengthTraining
        case "elliptical": return .elliptical
        case "rowing": return .rowing
        case "cross_training": return .crossTraining
        case "high_intensity_interval_training", "hiit": return .highIntensityIntervalTraining
        case "dance", "cardio_dance": return .cardioDance
        case "core_training": return .coreTraining
        case "pilates": return .pilates
        case "other": return .other
        default: return nil
        }
    }

    private static func workoutActivityDisplayName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return text("health.tool.workout.type.running")
        case .walking: return text("health.tool.workout.type.walking")
        case .cycling: return text("health.tool.workout.type.cycling")
        case .hiking: return text("health.tool.workout.type.hiking")
        case .badminton: return text("health.tool.workout.type.badminton")
        case .swimming: return text("health.tool.workout.type.swimming")
        case .yoga: return text("health.tool.workout.type.yoga")
        case .functionalStrengthTraining: return text("health.tool.workout.type.functional_strength")
        case .traditionalStrengthTraining: return text("health.tool.workout.type.traditional_strength")
        case .elliptical: return text("health.tool.workout.type.elliptical")
        case .rowing: return text("health.tool.workout.type.rowing")
        case .crossTraining: return text("health.tool.workout.type.cross_training")
        case .highIntensityIntervalTraining: return text("health.tool.workout.type.hiit")
        case .cardioDance: return text("health.tool.workout.type.dance")
        case .coreTraining: return text("health.tool.workout.type.core_training")
        case .pilates: return text("health.tool.workout.type.pilates")
        case .other: return text("health.tool.workout.type.other")
        default: return text("health.tool.workout.type.default")
        }
    }

    private static func formatDistanceMeters(_ meters: Double) -> String {
        if meters >= 1000 {
            return formatDoubleUnit(meters / 1000, key: "health.tool.unit.kilometers.precision")
        }
        return formatIntegerUnit(meters, key: "health.tool.unit.meters")
    }

    private static func formatDurationMinutes(_ minutes: Double) -> String {
        let hours = Int(minutes / 60)
        let mins = Int(minutes.truncatingRemainder(dividingBy: 60))
        if hours > 0 {
            return format("health.tool.unit.duration.hours_minutes", hours, mins)
        }
        return format("health.tool.unit.duration.minutes", mins)
    }

    private static func formatIntegerUnit(_ value: Double, key: String) -> String {
        format(key, Int(value.rounded()))
    }

    private static func formatDoubleUnit(_ value: Double, key: String) -> String {
        format(key, value)
    }

    private static func dateRangeText(_ start: Date, _ end: Date) -> String {
        let formatter = dayFormatter(calendar: .current)
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private static func dateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let count = max(0, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0)
        return (0...count).compactMap { calendar.date(byAdding: .day, value: $0, to: startDay) }
    }

    private static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func clockFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private static func displayDayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private static func displayTimeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private static func mealSegments() -> [MealSegment] {
        [
            MealSegment(label: text("health.tool.meal.late_night"), range: 0..<3),
            MealSegment(label: text("health.tool.meal.breakfast"), range: 3..<11),
            MealSegment(label: text("health.tool.meal.lunch"), range: 11..<13),
            MealSegment(label: text("health.tool.meal.afternoon_snack"), range: 13..<16),
            MealSegment(label: text("health.tool.meal.dinner"), range: 16..<19),
            MealSegment(label: text("health.tool.meal.evening_snack"), range: 19..<24)
        ]
    }
}

private struct QuantityMetric {
    let identifier: HKQuantityTypeIdentifier
    let unit: HKUnit
    let labelKey: String
    let formatter: (Double) -> String
}

private struct NutritionValue {
    let date: Date
    let value: Double
}

private struct NutritionSeries {
    let labelKey: String
    let unit: String
    let values: [NutritionValue]
}

private struct MealSegment {
    let label: String
    let range: Range<Int>

    func contains(_ hour: Int) -> Bool {
        range.contains(hour)
    }
}
