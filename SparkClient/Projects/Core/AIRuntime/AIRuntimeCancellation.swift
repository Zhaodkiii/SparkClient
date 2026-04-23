import Foundation

/// AI 生成链路的轻量取消令牌。
///
/// UI 会同时取消外层 `Task` 与这个令牌；Runtime / Gateway / 本地模型循环都只依赖
/// `checkCancellation()`，这样聊天、工具内抽取、文档抽取等 AI 流程可以共用同一套中断语义。
final class AIRuntimeCancellationToken: @unchecked Sendable {
    private let storage = Atomic(false)

    nonisolated var isCancelled: Bool {
        storage.value
    }

    nonisolated func cancel() {
        storage.value = true
    }

    nonisolated func checkCancellation() throws {
        if isCancelled || Task.isCancelled {
            throw CancellationError()
        }
    }
}
