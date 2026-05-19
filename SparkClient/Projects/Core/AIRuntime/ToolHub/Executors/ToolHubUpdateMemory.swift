import Foundation

extension ToolHub {
    func runUpdateMemory(invocation: ToolInvocation) async -> ToolExecutionResult {
        let original = (invocation.arguments["originalContent"] ?? invocation.arguments["original"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = (invocation.arguments["updatedContent"] ?? invocation.arguments["updated"] ?? invocation.arguments["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard original.isEmpty == false, updated.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.updateMemory,
                outputText: "记忆更新失败：需要 originalContent 与 updatedContent。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            guard let record = try await updateMemoryUseCase.execute(
                originalContentOrTitle: original,
                updatedContent: updated
            ) else {
                return ToolExecutionResult(
                    toolName: SparkToolName.updateMemory,
                    outputText: "记忆更新失败：未找到原始内容。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            }
            return ToolExecutionResult(
                toolName: SparkToolName.updateMemory,
                outputText: "记忆已更新：\(record.title)",
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.updateMemory,
                outputText: "记忆更新失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

}
