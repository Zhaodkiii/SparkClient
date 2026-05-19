import Foundation

extension ToolHub {
    func runCreateCanvas(invocation: ToolInvocation) -> ToolExecutionResult {
        let title = (invocation.arguments["title"] ?? "默认画布").trimmingCharacters(in: .whitespacesAndNewlines)
        let content = invocation.arguments["content"] ?? ""
        let canvasType = (invocation.arguments["type"] ?? "text").trimmingCharacters(in: .whitespacesAndNewlines)
        canvasStore[title] = content
        let kind = canvasType.isEmpty ? "text" : canvasType
        return ToolExecutionResult(
            toolName: SparkToolName.createCanvas,
            outputText: "画布已创建：\(title)，类型：\(kind)",
            sensitive: false,
            shouldBypassModel: true
        )
    }

}
