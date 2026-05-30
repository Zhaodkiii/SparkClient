import Foundation

nonisolated struct ChatToolBlockPayload: Codable, Equatable, Sendable {
    let name: String?
    let content: String
    /// 工具执行侧归一化参数（来自 `ToolExecutionResult.arguments`），供工具详情 Sheet。
    let invocationArguments: [String: String]?

    init(
        name: String?,
        content: String,
        invocationArguments: [String: String]? = nil
    ) {
        self.name = name
        self.content = content
        self.invocationArguments = invocationArguments
    }
}
