import Foundation

extension ToolHub {
    func runCreateKnowledgeDocument(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let title = (invocation.arguments["title"] ?? "未命名文档").trimmingCharacters(in: .whitespacesAndNewlines)
        let content = (invocation.arguments["content"] ?? invocation.arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.createKnowledgeDocument,
                outputText: "知识文档草稿生成失败：content 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }
        let resolvedTitle = title.isEmpty ? "未命名文档" : title
        logger.info(
            "create_knowledge_document 生成预览草稿，title=\(resolvedTitle), contentLength=\(content.count)",
            module: .aiConfig
        )

        let userFacing = "已生成知识库文档草稿「\(resolvedTitle)」，内容已附在消息内知识卡中，用户可点击保存到知识库。"
        if let threadID = context.threadID,
           let assistantID = context.assistantMessageClientID {
            let merge = structuredHealthCardMergeCoordinator
            let anchorToolCallID = normalizedToolCallID(from: context)
            Task {
                await merge.publishKnowledgeCards(
                    threadID: threadID,
                    assistantClientMessageID: assistantID,
                    cards: [ChatKnowledgeCard(title: resolvedTitle, content: content)],
                    anchorToolCallID: anchorToolCallID
                )
            }
        }
        return ToolExecutionResult(
            toolName: SparkToolName.createKnowledgeDocument,
            outputText: userFacing,
            sensitive: false,
            shouldBypassModel: true
        )
    }

}
