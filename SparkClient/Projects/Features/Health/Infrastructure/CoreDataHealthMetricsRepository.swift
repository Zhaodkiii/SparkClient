import CoreData
import Foundation

final class CoreDataHealthMetricsRepository: HealthMetricsRepository {
    private let coreDataStack: CoreDataStack
    private let logger: Logger

    init(coreDataStack: CoreDataStack, logger: Logger = ConsoleLogger()) {
        self.coreDataStack = coreDataStack
        self.logger = logger
    }

    func seedDefaultMetricsIfNeeded(for profileID: UUID) async throws {
        try await coreDataStack.performBackgroundTask { context in
            let request = HealthMetricEntity.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "profileID == %@", profileID as CVarArg)

            guard try context.count(for: request) == 0 else { return }

            let now = Date()
            let samples: [(HealthMetricType, Double, String, TimeInterval)] = [
                (.steps, 8234, "步", -3600 * 6),
                (.sleep, 7.6, "小时", -3600 * 12),
                (.heartRate, 68, "bpm", -3600 * 24),
                (.weight, 68.5, "kg", -3600 * 48),
                (.steps, 10342, "步", -3600 * 72),
                (.sleep, 7.2, "小时", -3600 * 96)
            ]

            for sample in samples {
                let entity = HealthMetricEntity(context: context)
                entity.id = UUID()
                entity.profileID = profileID
                entity.type = sample.0.rawValue
                entity.value = sample.1
                entity.unit = sample.2
                entity.recordedAt = now.addingTimeInterval(sample.3)
                entity.note = nil
            }
        }
    }

    func fetchRecentMetrics(for profileID: UUID, limit: Int) async throws -> [HealthMetric] {
        try await coreDataStack.performBackgroundTask { context in
            let request = HealthMetricEntity.fetchRequest()
            request.fetchLimit = limit
            request.predicate = NSPredicate(format: "profileID == %@", profileID as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "recordedAt", ascending: false)]
            return try context.fetch(request).compactMap { $0.toDomain() }
        }
    }
}

private extension HealthMetricEntity {
    func toDomain() -> HealthMetric? {
        guard
            let id,
            let profileID,
            let type,
            let metricType = HealthMetricType(rawValue: type),
            let unit,
            let recordedAt
        else {
            return nil
        }

        return HealthMetric(
            id: id,
            profileID: profileID,
            type: metricType,
            value: value,
            unit: unit,
            recordedAt: recordedAt,
            note: note
        )
    }
}
