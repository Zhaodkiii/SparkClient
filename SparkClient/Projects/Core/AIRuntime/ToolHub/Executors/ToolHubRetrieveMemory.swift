import Foundation

extension ToolHub {
    func runRetrieveMemory(invocation: ToolInvocation) async -> ToolExecutionResult {
        let query = (invocation.arguments["query"] ?? invocation.arguments["keyword"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let hits = try await retrieveMemoryUseCase.execute(keyword: query)
            if hits.isEmpty {
                return ToolExecutionResult(
                    toolName: SparkToolName.retrieveMemory,
                    outputText: "未检索到相关记忆。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            }
            let lines = hits.map { hit in
                "- \(hit.record.title)：\(hit.record.content)"
            }
            return ToolExecutionResult(
                toolName: SparkToolName.retrieveMemory,
                outputText: lines.joined(separator: "\n"),
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.retrieveMemory,
                outputText: "记忆检索失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

}
