import Foundation

/// 归并短时间内的多次 DB 通知 / 刷新请求，降低会话列表抖动。
///
/// 注意：这里必须是 throttle，而不是 debounce。流式 token 会持续写入 DB；
/// 如果每次通知都取消并重排刷新，UI 会等到流暂停后才更新，体感会变成 1s+ 跳字。
@MainActor
final class ChatLoadCoordinator {
    private var pending: Task<Void, Never>?
    private var latestOperation: (() async -> Void)?

    /// - Parameters:
    ///   - delayMs: 节流间隔。
    ///   - operation: 实际刷新（例如重新拉一页消息）。
    func schedule(delayMs: UInt64 = 120, operation: @escaping () async -> Void) {
        latestOperation = operation
        guard pending == nil else { return }
        pending = Task { [delayMs] in
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            guard Task.isCancelled == false else { return }
            let operation = latestOperation
            latestOperation = nil
            pending = nil
            await operation?()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        latestOperation = nil
    }
}
