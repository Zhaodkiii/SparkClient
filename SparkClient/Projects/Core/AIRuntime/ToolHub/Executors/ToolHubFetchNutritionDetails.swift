import Foundation

extension ToolHub {
    func runFetchNutrition(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments)
        do {
            let model = try await healthTool.fetchNutritionReadVisualization(from: range.start, to: range.end)
            let output = model.toReadableText()
            var sideEffects: [ToolSideEffect] = []
            if healthOutputContainsUserData(output),
               context.threadID != nil,
               context.assistantMessageClientID != nil {
                sideEffects = [.nutritionReadVisualization(model)]
            }
            return ToolExecutionResult(
                toolName: SparkToolName.fetchNutritionDetails,
                outputText: output,
                sensitive: healthOutputContainsUserData(output),
                shouldBypassModel: true,
                sideEffects: sideEffects
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.fetchNutritionDetails,
                outputText: error.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    ///
    /// AI 工具调用：执行【获取用户健身/运动记录】
    /// 入口：AI 助手调用 fetchWorkoutDetails 工具时会走进来
    /// 作用：查询健康数据 → 生成运动卡片 → 返回自然语言结果给AI展示

}
