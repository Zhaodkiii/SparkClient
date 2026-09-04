import CoreData
import Foundation

/// CoreData 堆栈管理类
/// 职责：
/// 1. 初始化 CoreData 容器（支持内存存储/本地存储）
/// 2. 提供主线程上下文（viewContext）供 UI 使用
/// 3. 提供安全的后台任务执行方法（自动保存/回滚）
/// 4. 自动处理数据库迁移
/// 5. 线程安全 + Sendable 兼容
final class CoreDataStack: @unchecked Sendable {

    // MARK: - 单例
    /// 全局共用的 CoreData 栈（生产环境）
    static let shared = CoreDataStack()

    /// 预览专用（内存存储，不会写入磁盘）
    @MainActor
    static let preview: CoreDataStack = {
        CoreDataStack(inMemory: true)
    }()

    // MARK: - 配置
    let logger: Logger        // 日志工具
    private let inMemory: Bool // 是否使用内存存储（预览/测试用）
    private let modelName: String // CoreData 模型文件名
    private let stateQueue = DispatchQueue(label: "spark.coredata.stack.state") // 线程安全队列
    private var containerStorage: NSPersistentContainer // CoreData 容器（存储区）

    // MARK: - 主线程上下文（UI 读取使用）
    /// UI 主线程使用的 NSManagedObjectContext
    /// 自动合并后台上下文的变化
    var viewContext: NSManagedObjectContext {
        stateQueue.sync { containerStorage.viewContext }
    }

    // MARK: - 初始化
    init(
        inMemory: Bool = false,
        modelName: String = "SparkClient",
        storeURL: URL? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.logger = logger
        self.inMemory = inMemory
        self.modelName = modelName

        // 创建并加载 CoreData 容器
        let bootContainer = Self.makeContainer(
            modelName: modelName,
            inMemory: inMemory,
            storeURL: storeURL ?? Self.defaultStoreURL()
        )
        self.containerStorage = bootContainer
    }

    // MARK: - 后台安全执行数据库任务（自动保存/回滚）
    /// 执行后台数据库任务
    /// 自动创建背景上下文 → 执行任务 → 有变更则保存 → 无变更直接返回
    /// - Parameter work: 后台任务（需要 Sendable）
    /// - Returns: 任务返回值
    func performBackgroundTask<T: Sendable>(
        _ work: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        let container = stateQueue.sync { containerStorage }

        // 用异步续体包装 CoreData 闭包，使其支持 async/await
        return try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                // 合并策略：冲突时以内存对象为准
                context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
                context.name = "backgroundContext"

                do {
                    // 执行业务逻辑
                    let value = try work(context)

                    // 如果有修改，自动保存
                    if context.hasChanges {
                        try context.save()
                    }

                    // 成功返回结果
                    continuation.resume(returning: value)

                } catch {
                    // 出错 → 回滚所有未提交修改
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - 串行写入上下文（修复 check-then-insert 并发重复插入）
    /// `performBackgroundTask` 每次创建独立上下文，多个写入可能并发执行：
    /// 两个任务同时「查不到 → 插入」会产生重复行（曾导致 Dictionary 唯一键崩溃）。
    /// 写入统一走这个长期持有的单一后台上下文（其私有队列天然串行）。
    private var writeContextStorage: NSManagedObjectContext?

    private func serializedWriteContext() -> NSManagedObjectContext {
        stateQueue.sync {
            if let existing = writeContextStorage {
                return existing
            }
            let context = containerStorage.newBackgroundContext()
            context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
            context.name = "serializedWriteContext"
            writeContextStorage = context
            return context
        }
    }

    /// 在共享串行写入上下文上执行写任务（自动保存/回滚）。
    /// 注意：work 内不得再次调用本方法或 `performBackgroundTask` 做嵌套写，否则死锁。
    func performSerializedBackgroundTask<T: Sendable>(
        _ work: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        let context = serializedWriteContext()
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let value = try work(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    // 长期持有的上下文每次任务后复位，避免注册对象无限累积。
                    context.reset()
                    continuation.resume(returning: value)
                } catch {
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - 创建并配置 CoreData 容器
    /// 创建 NSPersistentContainer
    /// 自动配置：迁移、存储路径、内存模式、合并策略
    private static func makeContainer(
        modelName: String,
        inMemory: Bool,
        storeURL: URL
    ) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: modelName)

        // 内存模式（预览/测试）
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // 确保存储目录存在
            let parent = storeURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: nil
            )
            container.persistentStoreDescriptions.first?.url = storeURL
        }

        // 自动迁移（自动升级数据库结构）
        for description in container.persistentStoreDescriptions {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }

        // 加载持久化存储
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load CoreData store: \(error)")
            }
        }

        // 配置主上下文：自动合并后台保存的变化
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.name = "viewContext"

        return container
    }

    // MARK: - 存储路径管理
    /// 基础存储目录：Application Support/SparkClient/CoreData/
    private static func baseStoreDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return base
            .appendingPathComponent("SparkClient", isDirectory: true)
            .appendingPathComponent("CoreData", isDirectory: true)
    }

    /// 多用户/隔离存储路径
    static func isolatedStoreURL(fileName: String) -> URL {
        baseStoreDirectory().appendingPathComponent(fileName)
    }

    /// 默认 SQLite 路径
    private static func defaultStoreURL() -> URL {
        isolatedStoreURL(fileName: "SparkClient.sqlite")
    }
}
