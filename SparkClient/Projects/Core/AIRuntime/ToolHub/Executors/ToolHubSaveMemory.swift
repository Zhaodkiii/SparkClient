import Foundation

extension ToolHub {
    func runSaveMemory(invocation: ToolInvocation) async -> ToolExecutionResult {
        let content = (invocation.arguments["content"] ?? invocation.arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.saveMemory,
                outputText: "记忆保存失败：content 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let preferences = await memoryPreferencesUseCase.load()
        guard preferences.isEnabled, preferences.allowToolWrite else {
            return ToolExecutionResult(
                toolName: SparkToolName.saveMemory,
                outputText: "记忆功能当前未允许写入。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let record = try await saveMemoryUseCase.execute(content: content)
            return ToolExecutionResult(
                toolName: SparkToolName.saveMemory,
                outputText: "记忆已保存：\(record.title)",
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.saveMemory,
                outputText: "记忆保存失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

}
