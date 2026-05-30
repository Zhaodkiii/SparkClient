import Foundation

/// 聊天内「工具详情」Sheet 的展示载荷（不入库）。
nonisolated struct ToolPreviewPrompt: Codable, Equatable, Sendable {
    let id: UUID
    let toolName: String
    let toolContent: String
    let toolArguments: [String: String]?
    let toolCallID: String?
    let threadID: UUID
    let sourceClientMessageID: UUID
    let relatedBlockIDs: [UUID]

    init(
        id: UUID = UUID(),
        toolName: String,
        toolContent: String,
        toolArguments: [String: String]? = nil,
        toolCallID: String?,
        threadID: UUID,
        sourceClientMessageID: UUID,
        relatedBlockIDs: [UUID]
    ) {
        self.id = id
        self.toolName = toolName
        self.toolContent = toolContent
        self.toolArguments = toolArguments
        self.toolCallID = toolCallID
        self.threadID = threadID
        self.sourceClientMessageID = sourceClientMessageID
        self.relatedBlockIDs = relatedBlockIDs
    }
}

extension ToolPreviewPrompt {
    /// 将工具调用参数字典格式化为详情 Sheet 可读文本。
    nonisolated static func displayText(for toolArguments: [String: String]) -> String {
        toolArguments
            .sorted { $0.key < $1.key }
            .map { key, value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? key : "\(key): \(trimmed)"
            }
            .joined(separator: "\n")
    }
}
