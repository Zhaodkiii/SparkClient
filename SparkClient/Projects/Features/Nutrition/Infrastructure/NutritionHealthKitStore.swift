import Foundation
import HealthKit

struct AppleHealthNutritionWriteResult: Sendable, Equatable {
    var intakeID: Int
    var appleHealthID: String?
}

struct AppleHealthEnergyBurnWriteResult: Sendable, Equatable {
    var energyBurnRecordID: Int
    var appleHealthID: String?
}

enum NutritionHealthKitStoreError: Error, LocalizedError {
    case unavailable
    case quantityTypesUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "HealthKit is not available on this device."
        case .quantityTypesUnavailable:
            return "Required HealthKit quantity types are unavailable."
        }
    }
}

/// HealthKit read/write for the Nutrition feature. Keeps HealthKit types out of UseCases and Views.
final class NutritionHealthKitStore: @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private let logger: Logger
    private let appBundleIdentifier: String

    init(
        logger: Logger = ConsoleLogger(),
        appBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "cn.Zhaodk.Health"
    ) {
        self.logger = logger
        self.appBundleIdentifier = appBundleIdentifier
    }

    func fetchExternalIntakeSamples(on date: Date) async throws -> [SparkNutritionAPI.AppleHealthIntakeSample] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NutritionHealthKitStoreError.unavailable
        }
        guard let types = nutritionQuantityTypes() else {
            throw NutritionHealthKitStoreError.quantityTypesUnavailable
        }

        try await requestAuthorization(readTypes: Set(types.values), writeTypes: [])

        let interval = dayInterval(for: date)
        async let energySamples = quantitySamples(type: types.energy, start: interval.start, end: interval.end)
        async let proteinSamples = quantitySamples(type: types.protein, start: interval.start, end: interval.end)
        async let carbSamples = quantitySamples(type: types.carbohydrates, start: interval.start, end: interval.end)
        async let fatSamples = quantitySamples(type: types.fat, start: interval.start, end: interval.end)

        let externalEnergy = try await energySamples.filter { isExternalSample($0) }
        let proteins = try await proteinSamples.filter { isExternalSample($0) }
        let carbs = try await carbSamples.filter { isExternalSample($0) }
        let fats = try await fatSamples.filter { isExternalSample($0) }

        return externalEnergy.map { energySample in
            let bundleID = sourceBundleIdentifier(for: energySample)
            let sourceName = sourceName(for: energySample)
            let timestamp = energySample.startDate
            var intakes: [SparkNutritionAPI.NutritionIntakeInput] = [
                intakeInput(
                    nutrientType: "energy_kcal",
                    value: energySample.quantity.doubleValue(for: .kilocalorie()),
                    unit: "kcal"
                )
            ]

            if let protein = matchingSample(in: proteins, near: timestamp, bundleID: bundleID) {
                intakes.append(
                    intakeInput(
                        nutrientType: "protein_g",
                        value: protein.quantity.doubleValue(for: .gram()),
                        unit: "g"
                    )
                )
            }
            if let carb = matchingSample(in: carbs, near: timestamp, bundleID: bundleID) {
                intakes.append(
                    intakeInput(
                        nutrientType: "carbohydrate_g",
                        value: carb.quantity.doubleValue(for: .gram()),
                        unit: "g"
                    )
                )
            }
            if let fat = matchingSample(in: fats, near: timestamp, bundleID: bundleID) {
                intakes.append(
                    intakeInput(
                        nutrientType: "fat_g",
                        value: fat.quantity.doubleValue(for: .gram()),
                        unit: "g"
                    )
                )
            }

            return SparkNutritionAPI.AppleHealthIntakeSample(
                appleHealthId: energySample.uuid.uuidString,
                occurredAt: timestamp,
                sourceBundleId: bundleID,
                sourceName: sourceName,
                intakes: intakes
            )
        }
    }

    func fetchEnergyBurnSamples(on date: Date) async throws -> [SparkNutritionAPI.AppleHealthEnergyBurnSample] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NutritionHealthKitStoreError.unavailable
        }
        guard
            let activeType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)
        else {
            throw NutritionHealthKitStoreError.quantityTypesUnavailable
        }

        try await requestAuthorization(readTypes: [activeType, basalType], writeTypes: [])

        let interval = dayInterval(for: date)
        async let activeSamples = quantitySamples(type: activeType, start: interval.start, end: interval.end)
        async let basalSamples = quantitySamples(type: basalType, start: interval.start, end: interval.end)

        let active = try await activeSamples
            .filter { isExternalSample($0) }
            .map { sample in
                SparkNutritionAPI.AppleHealthEnergyBurnSample(
                    appleHealthId: sample.uuid.uuidString,
                    burnedAt: sample.startDate,
                    energyKcal: sample.quantity.doubleValue(for: .kilocalorie()),
                    activityType: "active_energy",
                    source: "apple_health_import"
                )
            }
        let basal = try await basalSamples
            .filter { isExternalSample($0) }
            .map { sample in
                SparkNutritionAPI.AppleHealthEnergyBurnSample(
                    appleHealthId: sample.uuid.uuidString,
                    burnedAt: sample.startDate,
                    energyKcal: sample.quantity.doubleValue(for: .kilocalorie()),
                    activityType: "basal_energy",
                    source: "apple_health_import"
                )
            }
        return active + basal
    }

    func writeMealIntakes(from record: SparkNutritionAPI.RemoteMealRecord) async throws -> [AppleHealthNutritionWriteResult] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NutritionHealthKitStoreError.unavailable
        }
        guard let types = nutritionQuantityTypes() else {
            throw NutritionHealthKitStoreError.quantityTypesUnavailable
        }

        try await requestAuthorization(readTypes: Set(types.values), writeTypes: Set(types.values))

        var results: [AppleHealthNutritionWriteResult] = []
        for intake in record.intakes {
            guard let intakeID = intake.id else { continue }
            if let existingID = intake.appleHealthId, existingID.isEmpty == false {
                continue
            }
            guard let sample = try await writeIntakeSample(intake, consumedAt: record.consumedAt, types: types) else {
                continue
            }
            results.append(
                AppleHealthNutritionWriteResult(
                    intakeID: intakeID,
                    appleHealthID: sample.uuid.uuidString
                )
            )
        }
        return results
    }

    func writeEnergyBurn(
        energyKcal: Double,
        burnedAt: Date,
        activityType: String
    ) async throws -> String? {
        guard energyKcal > 0 else { return nil }
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NutritionHealthKitStoreError.unavailable
        }
        guard let activeType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw NutritionHealthKitStoreError.quantityTypesUnavailable
        }

        try await requestAuthorization(readTypes: [activeType], writeTypes: [activeType])

        let sample = HKQuantitySample(
            type: activeType,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal),
            start: burnedAt,
            end: burnedAt,
            metadata: [
                HKMetadataKeyExternalUUID: activityType,
                "SparkNutritionManualBurn": true
            ]
        )
        try await save(samples: [sample])
        return sample.uuid.uuidString
    }

    // MARK: - Private

    private struct NutritionQuantityTypes {
        var energy: HKQuantityType
        var protein: HKQuantityType
        var carbohydrates: HKQuantityType
        var fat: HKQuantityType

        var values: [HKQuantityType] {
            [energy, protein, carbohydrates, fat]
        }
    }

    private func nutritionQuantityTypes() -> NutritionQuantityTypes? {
        guard
            let protein = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
            let carbohydrates = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
            let fat = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal),
            let energy = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)
        else {
            return nil
        }
        return NutritionQuantityTypes(
            energy: energy,
            protein: protein,
            carbohydrates: carbohydrates,
            fat: fat
        )
    }

    private func writeIntakeSample(
        _ intake: SparkNutritionAPI.RemoteNutritionIntake,
        consumedAt: Date,
        types: NutritionQuantityTypes
    ) async throws -> HKQuantitySample? {
        let quantityType: HKQuantityType?
        let unit: HKUnit
        switch intake.nutrientType {
        case "energy_kcal", "energy":
            quantityType = types.energy
            unit = .kilocalorie()
        case "protein_g", "protein":
            quantityType = types.protein
            unit = .gram()
        case "carbohydrate_g", "carbohydrates", "carbohydrate":
            quantityType = types.carbohydrates
            unit = .gram()
        case "fat_g", "fat":
            quantityType = types.fat
            unit = .gram()
        default:
            quantityType = nil
            unit = .gram()
        }
        guard let quantityType, intake.value > 0 else { return nil }

        let sample = HKQuantitySample(
            type: quantityType,
            quantity: HKQuantity(unit: unit, doubleValue: intake.value),
            start: consumedAt,
            end: consumedAt
        )
        try await save(samples: [sample])
        return sample
    }

    private func intakeInput(nutrientType: String, value: Double, unit: String) -> SparkNutritionAPI.NutritionIntakeInput {
        SparkNutritionAPI.NutritionIntakeInput(
            nutrientType: nutrientType,
            value: value,
            unit: unit,
            source: "apple_health_import",
            confidence: nil
        )
    }

    private func isExternalSample(_ sample: HKQuantitySample) -> Bool {
        sourceBundleIdentifier(for: sample) != appBundleIdentifier
    }

    private func sourceBundleIdentifier(for sample: HKQuantitySample) -> String {
        sample.sourceRevision.source.bundleIdentifier
    }

    private func sourceName(for sample: HKQuantitySample) -> String {
        sample.sourceRevision.source.name
    }

    private func matchingSample(
        in samples: [HKQuantitySample],
        near date: Date,
        bundleID: String
    ) -> HKQuantitySample? {
        samples.first { sample in
            sourceBundleIdentifier(for: sample) == bundleID
                && abs(sample.startDate.timeIntervalSince(date)) < 1
        }
    }

    private func dayInterval(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? date
        return (start, end)
    }

    private func quantitySamples(type: HKQuantityType, start: Date, end: Date) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func save(samples: [HKQuantitySample]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(samples) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
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
}
