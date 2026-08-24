import Foundation

/// “获取可复用 Thread，必要时创建”的编排结果。
enum ChatThreadAcquisitionResult: Equatable, Sendable {
    case reuse(threadID: UUID, reason: ChatThreadReuseReason)
    case created(threadID: UUID)
    case requiresAISettings
}

/// 公共 Thread 获取/创建编排器（CHAT-000041）。
///
/// 负责在“纯选择器”之上叠加两件事：
/// 1. 近期活跃或最近未开始 Thread 命中时直接复用，不请求模型、不创建；
/// 2. 未命中且必须新建时，先校验可用模型，再通过公共单飞门保证同一复用范围内
///    并发请求最多创建一条 Thread（创建前在单飞门内二次复核最新列表）。
///
/// - Important: 单飞以 `memberID` 为维度分区：对话 Tab 传 nil（全局），医疗资料入口传严格同成员。
///   账号切换通过 `reset()` 清空 in-flight 状态（由 `ChatListViewModel.resetForSessionSwitch()` 触发）。
@MainActor
final class ChatThreadAcquisitionCoordinator {
    private let stateStore: ChatStateStore
    private let createThread: @MainActor (Int?) async -> UUID?
    private let reloadThreads: @MainActor () async -> Void
    private let isAccountActive: @MainActor (Int64) -> Bool
    private let logger: Logger
    /// 单飞在途任务表：同一 key 同时只有一个选择/创建任务在运行，其余请求共享其结果。
    private struct Flight {
        let token: UUID
        let task: Task<ChatThreadAcquisitionResult, Never>
    }
    private var inFlight: [String: Flight] = [:]

    init(
        stateStore: ChatStateStore,
        createThread: @escaping @MainActor (Int?) async -> UUID?,
        reloadThreads: @escaping @MainActor () async -> Void = {},
        isAccountActive: @escaping @MainActor (Int64) -> Bool = { _ in true },
        logger: Logger = ConsoleLogger()
    ) {
        self.stateStore = stateStore
        self.createThread = createThread
        self.reloadThreads = reloadThreads
        self.isAccountActive = isAccountActive
        self.logger = logger
    }

    /// 获取可复用 Thread，必要时创建。
    /// - Parameters:
    ///   - memberID: nil 为全局范围（对话 Tab），非 nil 为严格同成员（医疗资料入口）。
    ///   - hasAvailableChatModel: 可用模型校验入口；仅在必须新建时调用。
    func acquire(
        accountID: Int64,
        memberID: Int? = nil,
        hasAvailableChatModel: @escaping @MainActor () async -> Bool
    ) async -> ChatThreadAcquisitionResult {
        let key = Self.flightKey(accountID: accountID, memberID: memberID)
        if let flight = inFlight[key] {
            logger.info(
                "chat.thread.acquire.single_flight_joined key=\(key)",
                module: .general
            )
            let result = await flight.task.value
            // 只有 flight 发起者拥有 created 的补偿删除权限；等待者必须以 reuse 返回。
            if case .created(let threadID) = result {
                return .reuse(threadID: threadID, reason: .joinedCreation)
            }
            return result
        }

        let token = UUID()
        let task = Task<ChatThreadAcquisitionResult, Never> { [weak self] in
            guard let self else { return .requiresAISettings }
            return await self.runAcquire(
                accountID: accountID,
                memberID: memberID,
                hasAvailableChatModel: hasAvailableChatModel
            )
        }
        inFlight[key] = Flight(token: token, task: task)
        let result = await task.value
        if inFlight[key]?.token == token {
            inFlight[key] = nil
        }
        return result
    }

    /// 清空 in-flight 状态（账号切换时调用），避免跨账号共享 Thread。
    func reset() {
        for flight in inFlight.values {
            flight.task.cancel()
        }
        inFlight.removeAll()
    }

    private func runAcquire(
        accountID: Int64,
        memberID: Int?,
        hasAvailableChatModel: @MainActor () async -> Bool
    ) async -> ChatThreadAcquisitionResult {
        guard isAccountActive(accountID), Task.isCancelled == false else {
            return .requiresAISettings
        }

        // 在单飞门内重新加载并基于最新列表复核。
        await reloadThreads()
        guard isAccountActive(accountID), Task.isCancelled == false else {
            return .requiresAISettings
        }
        let decision = RecentActiveChatThreadSelector.selection(
            in: stateStore.threadItems,
            memberID: memberID
        )

        switch decision {
        case .reuse(let threadID, let reason):
            logger.info(
                "chat.thread.acquire decision=\(reason.logValue) thread=\(shortID(threadID)) key=\(Self.flightKey(accountID: accountID, memberID: memberID))",
                module: .general
            )
            return .reuse(threadID: threadID, reason: reason)
        case .noReusableThread:
            guard await hasAvailableChatModel() else {
                return .requiresAISettings
            }
            guard isAccountActive(accountID), Task.isCancelled == false else {
                return .requiresAISettings
            }

            // 模型检查期间其他入口可能已经创建 Thread；创建前必须再次复核。
            await reloadThreads()
            let secondDecision = RecentActiveChatThreadSelector.selection(
                in: stateStore.threadItems,
                memberID: memberID
            )
            switch secondDecision {
            case .reuse(let threadID, let reason):
                return .reuse(threadID: threadID, reason: reason)
            case .noReusableThread:
                break
            }

            guard isAccountActive(accountID), Task.isCancelled == false else {
                return .requiresAISettings
            }
            guard let threadID = await createThread(memberID) else {
                return .requiresAISettings
            }
            logger.info(
                "chat.thread.acquire decision=create thread=\(shortID(threadID)) key=\(Self.flightKey(accountID: accountID, memberID: memberID))",
                module: .general
            )
            return .created(threadID: threadID)
        }
    }

    static func flightKey(accountID: Int64, memberID: Int?) -> String {
        let scope = memberID.map { "member:\($0)" } ?? "global"
        return "account:\(accountID)-\(scope)"
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}

private extension ChatThreadReuseReason {
    var logValue: String {
        switch self {
        case .recentActive: return "recentActive"
        case .latestUnstarted: return "latestUnstarted"
        case .joinedCreation: return "joinedCreation"
        }
    }
}
