import CoreData
import Foundation

/// CoreData 基础设施入口：
/// 1) 统一容器初始化
/// 2) 提供后台写入通道
/// 3) 隔离持久化细节，供 Repository 层复用
final class CoreDataStack: @unchecked Sendable {
    static let shared = CoreDataStack()

    @MainActor
    static let preview: CoreDataStack = {
        let stack = CoreDataStack(inMemory: true)
        Task {
            try? await CoreDataHealthMetricsRepository(
                coreDataStack: stack,
                logger: ConsoleLogger()
            ).seedDefaultMetricsIfNeeded(for: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        }
        return stack
    }()

    let container: NSPersistentContainer
    let logger: Logger

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(inMemory: Bool = false, logger: Logger = ConsoleLogger()) {
        self.logger = logger
        self.container = NSPersistentContainer(name: "SparkClient")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load CoreData store: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.name = "viewContext"
    }

    func performBackgroundTask<T: Sendable>(
        _ work: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                context.name = "backgroundContext"

                do {
                    let value = try work(context)
                    // Repository 只关注业务写入；持久化提交在 Stack 层统一处理。
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: value)
                } catch {
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
