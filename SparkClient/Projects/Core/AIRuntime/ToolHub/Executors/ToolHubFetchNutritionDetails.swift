import Foundation

extension ToolHub {
    func runFetchNutrition(invocation: ToolInvocation) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments)
        let output = await healthTool.fetchNutritionDetails(from: range.start, to: range.end)
        return ToolExecutionResult(
            toolName: SparkToolName.fetchNutritionDetails,
            outputText: output,
            sensitive: healthOutputContainsUserData(output),
            shouldBypassModel: true
        )
    }

    ///
    /// AI 工具调用：执行【获取用户健身/运动记录】
    /// 入口：AI 助手调用 fetchWorkoutDetails 工具时会走进来
    /// 作用：查询健康数据 → 生成运动卡片 → 返回自然语言结果给AI展示

}
