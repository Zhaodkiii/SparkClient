import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

actor HealthKitHomeHealthDataRepository: HomeHealthDataRepository {
#if canImport(HealthKit)
    private let healthStore = HKHealthStore()
#endif

    func currentAuthorizationStatus() async -> HomeDashboard.HealthAuthorizationStatus {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }

        let statuses = readTypes.compactMap { sampleType in
            healthStore.authorizationStatus(for: sampleType)
        }

        if statuses.allSatisfy({ $0 == .notDetermined }) {
            return .notDetermined
        }

        if statuses.contains(.sharingDenied) {
            return .denied
        }

        return .authorized
#else
        return .unavailable
#endif
    }

    func requestAuthorizationIfNeeded() async throws -> HomeDashboard.HealthAuthorizationStatus {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }

        let status = await currentAuthorizationStatus()
        if case .authorized = status {
            return .authorized
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HomeDashboard.HealthAuthorizationStatus, Error>) in
            healthStore.requestAuthorization(toShare: [], read: Set(readTypes)) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                Task {
                    let updated = await self.currentAuthorizationStatus()
                    continuation.resume(returning: updated)
                }
            }
        }
#else
        return .unavailable
#endif
    }

    func fetchHealthBasics() async throws -> [HomeDashboard.HealthBasicItem] {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return unavailableItems
        }

        _ = try await requestAuthorizationIfNeeded()

        async let steps = fetchTodaySteps()
        async let weight = fetchLatestWeight()
        async let sleep = fetchLastSleepHours()
        async let heartRate = fetchLatestHeartRate()

        return [try await steps, try await weight, try await sleep, try await heartRate]
#else
        return unavailableItems
#endif
    }

    private var unavailableItems: [HomeDashboard.HealthBasicItem] {
        [
            HomeDashboard.HealthBasicItem(id: .steps, value: nil, unit: "steps", symbol: "figure.walk.motion", recordedAt: nil),
            HomeDashboard.HealthBasicItem(id: .weight, value: nil, unit: "kg", symbol: "scalemass.fill", recordedAt: nil),
            HomeDashboard.HealthBasicItem(id: .sleep, value: nil, unit: "h", symbol: "moon.stars.fill", recordedAt: nil),
            HomeDashboard.HealthBasicItem(id: .heartRate, value: nil, unit: "bpm", symbol: "heart.text.square.fill", recordedAt: nil)
        ]
    }
}

#if canImport(HealthKit)
private extension HealthKitHomeHealthDataRepository {
    var readTypes: [HKSampleType] {
        var types: [HKSampleType] = []

        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.append(steps)
        }
        if let weight = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            types.append(weight)
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.append(sleep)
        }
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.append(heartRate)
        }

        return types
    }

    func fetchTodaySteps() async throws -> HomeDashboard.HealthBasicItem {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return HomeDashboard.HealthBasicItem(id: .steps, value: nil, unit: "steps", symbol: "figure.walk.motion", recordedAt: nil)
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        let sum = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double?, Error>) in
            let query = HKStatisticsQuery(quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = result?.sumQuantity()?.doubleValue(for: HKUnit.count())
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }

        return HomeDashboard.HealthBasicItem(
            id: .steps,
            value: sum,
            unit: "steps",
            symbol: "figure.walk.motion",
            recordedAt: Date()
        )
    }

    func fetchLatestWeight() async throws -> HomeDashboard.HealthBasicItem {
        let sample = try await fetchLatestQuantitySample(for: .bodyMass)
        let value = sample?.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))

        return HomeDashboard.HealthBasicItem(
            id: .weight,
            value: value,
            unit: "kg",
            symbol: "scalemass.fill",
            recordedAt: sample?.endDate
        )
    }

    func fetchLatestHeartRate() async throws -> HomeDashboard.HealthBasicItem {
        let sample = try await fetchLatestQuantitySample(for: .heartRate)
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let value = sample?.quantity.doubleValue(for: unit)

        return HomeDashboard.HealthBasicItem(
            id: .heartRate,
            value: value,
            unit: "bpm",
            symbol: "heart.text.square.fill",
            recordedAt: sample?.endDate
        )
    }

    func fetchLastSleepHours() async throws -> HomeDashboard.HealthBasicItem {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return HomeDashboard.HealthBasicItem(id: .sleep, value: nil, unit: "h", symbol: "moon.stars.fill", recordedAt: nil)
        }

        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let casted = (results as? [HKCategorySample]) ?? []
                continuation.resume(returning: casted)
            }
            healthStore.execute(query)
        }

        let sleepingSamples = samples.filter { $0.value >= HKCategoryValueSleepAnalysis.asleep.rawValue }
        let duration = sleepingSamples.reduce(0.0) { partial, sample in
            partial + sample.endDate.timeIntervalSince(sample.startDate)
        }

        return HomeDashboard.HealthBasicItem(
            id: .sleep,
            value: duration > 0 ? duration / 3600.0 : nil,
            unit: "h",
            symbol: "moon.stars.fill",
            recordedAt: sleepingSamples.first?.endDate
        )
    }

    func fetchLatestQuantitySample(for identifier: HKQuantityTypeIdentifier) async throws -> HKQuantitySample? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: quantityType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: results?.first as? HKQuantitySample)
            }
            healthStore.execute(query)
        }
    }
}
#endif
