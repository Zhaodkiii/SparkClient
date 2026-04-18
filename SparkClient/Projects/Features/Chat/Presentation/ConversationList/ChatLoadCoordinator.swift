import Foundation

/// 归并短时间内的多次 DB 通知 / 刷新请求，降低会话列表抖动。
@MainActor
final class ChatLoadCoordinator {
    private var pending: Task<Void, Never>?

    /// - Parameters:
    ///   - delayMs: 去抖间隔。
    ///   - operation: 实际刷新（例如重新拉一页消息）。
    func schedule(delayMs: UInt64 = 120, operation: @escaping () async -> Void) {
        pending?.cancel()
        pending = Task { [delayMs] in
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            guard Task.isCancelled == false else { return }
            await operation()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
