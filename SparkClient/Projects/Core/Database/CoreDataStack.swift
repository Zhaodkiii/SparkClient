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
        CoreDataStack(inMemory: true)
    }()

    let logger: Logger
    private let inMemory: Bool
    private let modelName: String
    private let stateQueue = DispatchQueue(label: "spark.coredata.stack.state")
    private var containerStorage: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        stateQueue.sync { containerStorage.viewContext }
    }

    init(
        inMemory: Bool = false,
        modelName: String = "SparkClient",
        storeURL: URL? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.logger = logger
        self.inMemory = inMemory
        self.modelName = modelName
        let bootContainer = Self.makeContainer(
            modelName: modelName,
            inMemory: inMemory,
            storeURL: storeURL ?? Self.defaultStoreURL()
        )
        self.containerStorage = bootContainer
    }

    func performBackgroundTask<T: Sendable>(
        _ work: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        let container = stateQueue.sync { containerStorage }
        return try await withCheckedThrowingContinuation { continuation in
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

    private static func makeContainer(
        modelName: String,
        inMemory: Bool,
        storeURL: URL
    ) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: modelName)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            let parent = storeURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: nil
            )
            container.persistentStoreDescriptions.first?.url = storeURL
        }

        for description in container.persistentStoreDescriptions {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load CoreData store: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.name = "viewContext"
        return container
    }

    private static func baseStoreDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SparkClient", isDirectory: true)
            .appendingPathComponent("CoreData", isDirectory: true)
    }

    static func isolatedStoreURL(fileName: String) -> URL {
        baseStoreDirectory().appendingPathComponent(fileName)
    }

    private static func defaultStoreURL() -> URL {
        isolatedStoreURL(fileName: "SparkClient.sqlite")
    }
}
