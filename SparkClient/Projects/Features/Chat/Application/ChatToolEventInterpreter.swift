import Foundation

/// 工具事件解释器：
/// - 新流程下，工具展示以 `ChatMessageBlock` 为唯一真相源；
/// - 不再把 toolName/toolContent/operational* 这类旧运行时附件落入正式消息，避免重复存储与重复渲染；
/// - 富 UI 与知识卡由 `ToolHub` 发布 `ChatRunEvent`，最终落到 `ChatMessageBlockEntity`。
struct ChatToolEventInterpreter: Sendable {
    let logger: Logger

    init(logger: Logger = ConsoleLogger()) {
        self.logger = logger
    }

    /// 解释一次助手输出，生成标准附件集合（仅工具运行时附件）。
    func interpret(
        kind: ChatMessageKind,
        text: String,
        toolName: String?,
        toolContent: String?
    ) -> ChatToolInterpretationResult {
        let result = ChatToolInterpretationResult(
            attachments: [],
            toolAttachmentCount: 0,
            knowledgeCardAttachmentCount: 0,
            richAttachmentCount: 0
        )
        logger.debug(
            "工具事件解释（block-only） kind=\(kind.rawValue) textLen=\(text.count) tool=\(toolName ?? "-") toolAttach=0",
            module: .general
        )
        return result
    }
}

struct ChatToolInterpretationResult: Sendable {
    let attachments: [ChatAttachment]
    let toolAttachmentCount: Int
    let knowledgeCardAttachmentCount: Int
    let richAttachmentCount: Int
}
