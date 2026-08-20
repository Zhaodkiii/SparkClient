import Foundation
import HealthKit

/// 运动健康模块的 HealthKit 读取封装。
///
/// 只读不写：拉取当日 8 项健康指标（睡眠、步数、运动记录、热量消耗、站立小时、
/// 总锻炼时长、血氧饱和度、心率），统一转换为 ``FitnessMetricValue``。
///
/// 设计原则与 `NutritionHealthKitStore` 一致：UseCase / View 不直接依赖 HKHealthStore，
/// 所有 HealthKit 类型隔离在本文件内。
final class FitnessHealthKitStore: @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private let logger: Logger

    init(logger: Logger = ConsoleLogger()) {
        self.logger = logger
    }

    /// 默认步数日目标。
    static let defaultStepGoal = 10_000

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.categoryType(forIdentifier: .appleStandHour)!,
            HKObjectType.workoutType(),
        ]
        return types
    }

    /// 请求读取运动健康所需类型的权限（不请求写权限）。
    func requestAuthorization() async throws {
        guard isHealthDataAvailable else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: Self.readTypes) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// 并发拉取当日 8 项 HealthKit 指标，单项失败不影响其余指标。
    func loadMetrics(on date: Date) async -> [FitnessMetricValue] {
        guard isHealthDataAvailable else {
            return FitnessMetricValue.healthPlaceholders
        }
        try? await requestAuthorization()

        let interval = Self.dayInterval(for: date)
        let start = interval.start
        let end = interval.end

        async let steps = cumulativeTotal(.stepCount, unit: .count(), start: start, end: end)
        async let calories = cumulativeTotal(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let exercise = cumulativeTotal(.appleExerciseTime, unit: .minute(), start: start, end: end)
        async let stand = standHourTotal(start: start, end: end)
        async let sleepMinutes = sleepDurationMinutes(start: start, end: end)
        async let workout = latestWorkout(start: start, end: end)
        async let oxygen = latestQuantitySample(.oxygenSaturation, unit: .percent(), start: start, end: end)
        async let heartRate = latestQuantitySample(.heartRate, unit: .count().unitDivided(by: .minute()), start: start, end: end)

        let (
            stepsValue, caloriesValue, exerciseValue, standValue,
            sleepValue, workoutValue, oxygenValue, heartRateValue
        ) = await (steps, calories, exercise, stand, sleepMinutes, workout, oxygen, heartRate)

        return [
            Self.sleepMetric(minutes: sleepValue),
            Self.stepsMetric(steps: stepsValue),
            Self.workoutMetric(workout: workoutValue),
            Self.caloriesMetric(value: caloriesValue),
            Self.standHourMetric(value: standValue),
            Self.exerciseTimeMetric(value: exerciseValue),
            Self.bloodOxygenMetric(value: oxygenValue?.value, date: oxygenValue?.date),
            Self.heartRateMetric(value: heartRateValue?.value, date: heartRateValue?.date),
        ]
    }

    // MARK: - 指标组装

    private static func sleepMetric(minutes: Double?) -> FitnessMetricValue {
        guard let minutes, minutes > 0 else { return .noData(.sleep) }
        return FitnessMetricValue(
            type: .sleep,
            value: minutes,
            unit: "",
            displayText: Self.sleepDisplayText(minutes: minutes),
            timestamp: nil,
            status: .normal,
            label: nil
        )
    }

    private static func stepsMetric(steps: Double?) -> FitnessMetricValue {
        let count = steps.map(Int.init) ?? 0
        return FitnessMetricValue(
            type: .steps,
            value: steps,
            unit: "",
            displayText: "\(count) / \(defaultStepGoal)",
            timestamp: nil,
            status: .normal,
            label: nil
        )
    }

    private static func workoutMetric(workout: WorkoutReading?) -> FitnessMetricValue {
        guard let workout else { return .noData(.workout) }
        return FitnessMetricValue(
            type: .workout,
            value: workout.durationMinutes,
            unit: "分钟",
            displayText: "\(Self.formatMinutes(workout.durationMinutes))分钟",
            timestamp: workout.date,
            status: .normal,
            label: workout.activityName
        )
    }

    private static func caloriesMetric(value: Double?) -> FitnessMetricValue {
        guard let value else { return .noData(.calories) }
        return FitnessMetricValue(
            type: .calories,
            value: value,
            unit: "kcal",
            displayText: "\(Int(value.rounded()))",
            timestamp: nil,
            status: .normal,
            label: L10n.text("fitness.card.calories.subtitle", fallback: "运动消耗")
        )
    }

    private static func standHourMetric(value: Double?) -> FitnessMetricValue {
        guard let value else { return .noData(.standHour) }
        return FitnessMetricValue(
            type: .standHour,
            value: value,
            unit: "小时",
            displayText: "\(Int(value))",
            timestamp: nil,
            status: .normal,
            label: nil
        )
    }

    private static func exerciseTimeMetric(value: Double?) -> FitnessMetricValue {
        guard let value else { return .noData(.exerciseTime) }
        return FitnessMetricValue(
            type: .exerciseTime,
            value: value,
            unit: "分钟",
            displayText: "\(Int(value))",
            timestamp: nil,
            status: .normal,
            label: nil
        )
    }

    private static func bloodOxygenMetric(value: Double?, date: Date?) -> FitnessMetricValue {
        guard let value else { return .noData(.bloodOxygen, unit: "%") }
        let status: FitnessMetricStatus = value < 95 ? .low : .normal
        return FitnessMetricValue(
            type: .bloodOxygen,
            value: value,
            unit: "%",
            displayText: "\(Int(value.rounded()))",
            timestamp: date,
            status: status,
            label: nil
        )
    }

    private static func heartRateMetric(value: Double?, date: Date?) -> FitnessMetricValue {
        guard let value else { return .noData(.heartRate) }
        return FitnessMetricValue(
            type: .heartRate,
            value: value,
            unit: "次/分钟",
            displayText: "\(Int(value.rounded()))",
            timestamp: date,
            status: .normal,
            label: nil
        )
    }

    // MARK: - HealthKit 查询

    private struct SampleReading {
        let value: Double
        let date: Date
    }

    private struct WorkoutReading {
        let durationMinutes: Double
        let date: Date
        let activityName: String
    }

    private func cumulativeTotal(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    self.logger.warning("运动健康 cumulativeSum 查询失败 identifier=\(identifier.rawValue) error=\(error.localizedDescription)", module: .fitness)
                }
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sum.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func latestQuantitySample(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> SampleReading? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { (continuation: CheckedContinuation<SampleReading?, Never>) in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    self.logger.warning("运动健康 latestSample 查询失败 identifier=\(identifier.rawValue) error=\(error.localizedDescription)", module: .fitness)
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: SampleReading(value: sample.quantity.doubleValue(for: unit), date: sample.endDate)
                )
            }
            healthStore.execute(query)
        }
    }

    private func standHourTotal(start: Date, end: Date) async -> Double? {
        guard let standType = HKCategoryType.categoryType(forIdentifier: .appleStandHour) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let query = HKSampleQuery(
                sampleType: standType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    self.logger.warning("运动健康站立小时查询失败 error=\(error.localizedDescription)", module: .fitness)
                }
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let stood = samples.filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count
                continuation.resume(returning: Double(stood))
            }
            healthStore.execute(query)
        }
    }

    private func sleepDurationMinutes(start: Date, end: Date) async -> Double? {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    self.logger.warning("运动健康睡眠查询失败 error=\(error.localizedDescription)", module: .fitness)
                }
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let asleep: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                let totalSeconds = samples
                    .filter { asleep.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let minutes = totalSeconds / 60.0
                continuation.resume(returning: minutes > 0 ? minutes : nil)
            }
            healthStore.execute(query)
        }
    }

    private func latestWorkout(start: Date, end: Date) async -> WorkoutReading? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { (continuation: CheckedContinuation<WorkoutReading?, Never>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    self.logger.warning("运动健康运动记录查询失败 error=\(error.localizedDescription)", module: .fitness)
                }
                guard let workout = samples?.first as? HKWorkout else {
                    continuation.resume(returning: nil)
                    return
                }
                let minutes = workout.duration / 60.0
                continuation.resume(
                    returning: WorkoutReading(
                        durationMinutes: minutes,
                        date: workout.endDate,
                        activityName: Self.workoutActivityName(workout.workoutActivityType)
                    )
                )
            }
            healthStore.execute(query)
        }
    }

    // MARK: - 工具

    private static func dayInterval(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    private static func sleepDisplayText(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let hours = total / 60
        let mins = total % 60
        if hours > 0 {
            return "\(hours)h\(mins)m"
        }
        return "\(mins)m"
    }

    private static func formatMinutes(_ minutes: Double) -> String {
        let value = Int(minutes.rounded())
        return String(value)
    }

    private static func workoutActivityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return L10n.text("fitness.workout.running", fallback: "跑步")
        case .walking: return L10n.text("fitness.workout.walking", fallback: "步行")
        case .cycling: return L10n.text("fitness.workout.cycling", fallback: "骑行")
        case .swimming: return L10n.text("fitness.workout.swimming", fallback: "游泳")
        case .yoga: return L10n.text("fitness.workout.yoga", fallback: "瑜伽")
        case .badminton: return L10n.text("fitness.workout.badminton", fallback: "羽毛球")
        case .traditionalStrengthTraining: return L10n.text("fitness.workout.strength", fallback: "力量训练")
        case .highIntensityIntervalTraining: return L10n.text("fitness.workout.hiit", fallback: "高强度间歇训练")
        default: return L10n.text("fitness.workout.generic", fallback: "运动")
        }
    }
}