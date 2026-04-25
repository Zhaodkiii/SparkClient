import Foundation

/// 工具事件解释器：
/// - 仅生成运行时工具类附件（`operationalState` 等），由 `ChatToolRuntimeAttachmentBuilder` 从 toolName/toolContent 解析。
/// - 富 UI 与知识卡附件仅在 `ToolHub` 调用工具时经 `StructuredHealthCardMergeCoordinator` 异步合并，不经此处与 `SendChatMessageUseCase`。
struct ChatToolEventInterpreter: Sendable {
    let logger: Logger
    let runtimeAttachmentBuilder: ChatToolRuntimeAttachmentBuilder

    init(
        logger: Logger = ConsoleLogger(),
        runtimeAttachmentBuilder: ChatToolRuntimeAttachmentBuilder = ChatToolRuntimeAttachmentBuilder()
    ) {
        self.logger = logger
        self.runtimeAttachmentBuilder = runtimeAttachmentBuilder
    }

    /// 解释一次助手输出，生成标准附件集合（仅工具运行时附件）。
    func interpret(
        kind: ChatMessageKind,
        text: String,
        toolName: String?,
        toolContent: String?
    ) -> ChatToolInterpretationResult {
        let toolAttachments = makeToolAttachments(toolName: toolName, toolContent: toolContent)
        let result = ChatToolInterpretationResult(
            attachments: toolAttachments,
            toolAttachmentCount: toolAttachments.count,
            knowledgeCardAttachmentCount: 0,
            richAttachmentCount: 0
        )
        logger.debug(
            "工具事件解释（仅运行时附件） kind=\(kind.rawValue) textLen=\(text.count) tool=\(toolName ?? "-") toolAttach=\(result.toolAttachmentCount)",
            module: .general
        )
        return result
    }

    private func makeToolAttachments(
        toolName: String?,
        toolContent: String?
    ) -> [ChatAttachment] {
        runtimeAttachmentBuilder.build(toolName: toolName, toolContent: toolContent)
    }
}

struct ChatToolInterpretationResult: Sendable {
    let attachments: [ChatAttachment]
    let toolAttachmentCount: Int
    let knowledgeCardAttachmentCount: Int
    let richAttachmentCount: Int
}
