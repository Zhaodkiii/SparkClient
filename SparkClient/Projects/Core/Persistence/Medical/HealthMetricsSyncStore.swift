import CoreData
import Foundation

actor HealthMetricsSyncStore {
    private let coreDataStack: CoreDataStack
    private let logger: Logger

    init(coreDataStack: CoreDataStack, logger: Logger = ConsoleLogger()) {
        self.coreDataStack = coreDataStack
        self.logger = logger
    }

    func loadAll() async throws -> [SyncedHealthMetric] {
        try await coreDataStack.performBackgroundTask { context in
            let request = HealthMetricEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "recordedAt", ascending: false)]
            let entities = try context.fetch(request)
            return entities.compactMap { entity in
                guard
                    let id = entity.id,
                    let profileID = entity.profileID,
                    let typeRaw = entity.type,
                    let type = HealthMetricType(rawValue: typeRaw),
                    let unit = entity.unit,
                    let recordedAt = entity.recordedAt
                else {
                    return nil
                }
                return SyncedHealthMetric(
                    id: id,
                    profileID: profileID,
                    type: type,
                    value: entity.value,
                    unit: unit,
                    recordedAt: recordedAt,
                    note: entity.note,
                    updatedAt: recordedAt
                )
            }
        }
    }

    func overwriteAll(with metrics: [SyncedHealthMetric]) async throws {
        try await coreDataStack.performBackgroundTask { context in
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: HealthMetricEntity.fetchRequest())
            deleteRequest.resultType = .resultTypeObjectIDs
            if let result = try context.execute(deleteRequest) as? NSBatchDeleteResult,
               let objectIDs = result.result as? [NSManagedObjectID],
               !objectIDs.isEmpty {
                let changes = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
            }

            for metric in metrics {
                let entity = HealthMetricEntity(context: context)
                entity.id = metric.id
                entity.profileID = metric.profileID
                entity.type = metric.type.rawValue
                entity.value = metric.value
                entity.unit = metric.unit
                entity.recordedAt = metric.recordedAt
                entity.note = metric.note
            }
            self.logger.info("已覆盖写入健康指标本地快照，count=\(metrics.count)", category: "medical_sync")
        }
    }
}
