import Foundation

/// 人机交互请求的显式结果，区分成功、用户取消、队列/系统冲突。
enum InteractionResult<Success: Sendable>: Sendable {
    case success(Success)
    case cancelled
    case conflict
}

nonisolated struct ToolConsentDecision: Codable, Equatable, Sendable {
    let allowed: Bool
    let rememberTool: Bool
}
