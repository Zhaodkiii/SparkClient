import Foundation

/// 聊天内「工具详情」Sheet 的展示载荷（不入库）。
struct ToolPreviewPrompt: Codable, Equatable, Sendable {
    let id: UUID
    let toolName: String
    let toolContent: String
    let toolCallID: String?
    let threadID: UUID
    let sourceClientMessageID: UUID
    let relatedBlockIDs: [UUID]

    init(
        id: UUID = UUID(),
        toolName: String,
        toolContent: String,
        toolCallID: String?,
        threadID: UUID,
        sourceClientMessageID: UUID,
        relatedBlockIDs: [UUID]
    ) {
        self.id = id
        self.toolName = toolName
        self.toolContent = toolContent
        self.toolCallID = toolCallID
        self.threadID = threadID
        self.sourceClientMessageID = sourceClientMessageID
        self.relatedBlockIDs = relatedBlockIDs
    }
}
