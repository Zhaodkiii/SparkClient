import Foundation

extension ToolHub {
    func runSearchKnowledgeBag(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let query = invocation.arguments["query"] ?? invocation.arguments["content"] ?? ""
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.searchKnowledgeBag,
                outputText: "知识库检索失败：query 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let results = try await searchKnowledgeUseCase.execute(query: trimmed, limit: 5)
            guard results.isEmpty == false else {
                return ToolExecutionResult(
                    toolName: SparkToolName.searchKnowledgeBag,
                    outputText: "知识库未匹配到相关文档。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            }

            let lines = results.enumerated().map { index, result in
                let prefix = "[\(index + 1)] \(result.title)"
                return "\(prefix)\n\(result.excerpt)"
            }
            let body = lines.joined(separator: "\n\n")
            let l10n = AIPromptL10n(locale: .current)
            let title = l10n.tool("tool.ui.knowledge.search_title", fallback: "Knowledge Search")
            if let threadID = context.threadID,
               let assistantID = context.assistantMessageClientID {
                let merge = structuredHealthCardMergeCoordinator
                let anchorToolCallID = normalizedToolCallID(from: context)
                Task {
                    await merge.insertKnowledgeCardsWhenAssistantMessageReady(
                        threadID: threadID,
                        assistantClientMessageID: assistantID,
                        cards: [ChatKnowledgeCard(title: title, content: body, showsSaveAndCopy: false)],
                        anchorToolCallID: anchorToolCallID
                    )
                }
            }
            return ToolExecutionResult(
                toolName: SparkToolName.searchKnowledgeBag,
                outputText: body,
                sensitive: false,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.searchKnowledgeBag,
                outputText: "知识库搜索失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

}
