import CoreData
import Foundation

/// 聊天域单一数据库入口：串行化所有 Core Data 访问，并在写成功后广播 ``Notification/Name/sparkChatDatabaseDidChange``。
/// 对齐 Signal `SDSDatabaseStorage` 的「单写队列 + 显式事务边界」思路（引擎仍为 Core Data）。
actor ChatDatabaseKernel {
    private let stack: CoreDataStack
    private let snapshotStore: SessionSnapshotStore
    private let logger: Logger

    init(
        coreDataStack: CoreDataStack,
        snapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        logger: Logger = ConsoleLogger()
    ) {
        self.stack = coreDataStack
        self.snapshotStore = snapshotStore
        self.logger = logger
    }

    private func currentAccountID() async -> Int64? {
        await snapshotStore.load()?.accountID
    }

    /// 只读路径；未登录时 `accountID` 为 `nil`，由闭包自行返回空结果。
    func read<T: Sendable>(
        _ work: @Sendable @escaping (NSManagedObjectContext, Int64?) throws -> T
    ) async throws -> T {
        let accountID = await currentAccountID()
        return try await stack.performBackgroundTask { context in
            try work(context, accountID)
        }
    }

    /// 写入路径；未登录时抛出 ``ChatDatabaseKernelError/notAuthenticated``。
    func write<T: Sendable>(
        postChangeNotification: Bool = true,
        _ work: @Sendable @escaping (NSManagedObjectContext, Int64) throws -> T
    ) async throws -> T {
        guard let accountID = await currentAccountID() else {
            throw ChatDatabaseKernelError.notAuthenticated
        }
        let value = try await stack.performBackgroundTask { context in
            try work(context, accountID)
        }
        if postChangeNotification {
            await self.postChangeNotification()
        }
        return value
    }

    /// 写入但不在末尾发通知（用于同一逻辑链内多次写，由最外层统一 `post`）。
    func writeWithoutNotification<T: Sendable>(
        _ work: @Sendable @escaping (NSManagedObjectContext, Int64) throws -> T
    ) async throws -> T {
        try await write(postChangeNotification: false, work)
    }

    func postChangeNotification(_ event: ChatConversationChangeEvent? = nil) async {
        await MainActor.run {
            NotificationCenter.default.post(name: .sparkChatDatabaseDidChange, object: event)
        }
    }
}

enum ChatDatabaseKernelError: Error {
    case notAuthenticated
}
