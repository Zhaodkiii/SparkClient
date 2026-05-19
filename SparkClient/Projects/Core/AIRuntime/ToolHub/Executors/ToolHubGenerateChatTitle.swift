import Foundation

extension ToolHub {
    func runGenerateChatTitle(invocation: ToolInvocation) -> ToolExecutionResult {
        let source = invocation.arguments["content"] ?? invocation.arguments["query"] ?? "新对话"
        let title = String(source.trimmingCharacters(in: .whitespacesAndNewlines).prefix(18))
        return ToolExecutionResult(
            toolName: SparkToolName.generateChatTitle,
            outputText: title.isEmpty ? "新对话" : title,
            sensitive: false,
            shouldBypassModel: true
        )
    }

}
