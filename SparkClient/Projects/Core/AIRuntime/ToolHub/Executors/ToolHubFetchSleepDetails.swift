import Foundation

extension ToolHub {
    func runFetchSleep(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments, fallbackDays: 2)
        do {
            let model = try await healthTool.fetchSleepDetails(from: range.start, to: range.end)
            // 仅向模型提供可读摘要；完整结构由协调器异步写入 `healthSleepVisualization`，不经工具输出再解码。
            let outputText = model.toReadableText()
            if let threadID = context.threadID,
               let assistantID = context.assistantMessageClientID {
                let merge = structuredHealthCardMergeCoordinator
                let normalizedToolCallID = context.pendingToolCallID?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    await merge.insertHealthSleepVisualizationWhenAssistantMessageReady(
                        threadID: threadID,
                        assistantClientMessageID: assistantID,
                        model: model,
                        anchorToolCallID: (normalizedToolCallID?.isEmpty == false ? normalizedToolCallID : nil),
                        )
                }
            }
            return ToolExecutionResult(
                toolName: SparkToolName.fetchSleepDetails,
                outputText: outputText,
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.fetchSleepDetails,
                outputText: "睡眠查询失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }


}
