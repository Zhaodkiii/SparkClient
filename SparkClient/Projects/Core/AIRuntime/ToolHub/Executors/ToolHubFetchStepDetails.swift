import Foundation

extension ToolHub {
    func runFetchSteps(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        // 取数前校验：成员是否绑定苹果健康设备（未选择成员时先弹选择卡片，等待用户选择后继续）；未绑定/无权限则按无数据处理并引导绑定。
        let accessCheck = await healthDataAccessCheck(
            invocation: invocation,
            context: context,
            toolName: .fetchStepDetails
        )
        if let denied = accessCheck.denied {
            return denied
        }

        let range = resolveHealthRange(arguments: invocation.arguments)
        do {
            let model = try await healthTool.fetchStepVisualization(from: range.start, to: range.end)
            let output = model.toReadableText()
            var sideEffects: [ToolSideEffect] = []
            if healthOutputContainsUserData(output),
               context.threadID != nil,
               context.assistantMessageClientID != nil {
                sideEffects = [.stepVisualization(model)]
            }
            return ToolExecutionResult(
                toolName: SparkToolName.fetchStepDetails,
                outputText: output,
                sensitive: healthOutputContainsUserData(output),
                shouldBypassModel: true,
                resolvedMemberID: accessCheck.resolvedMemberID,
                sideEffects: sideEffects
            )
        } catch {
            let output = healthNoDataDiagnosticIfNeeded(error.localizedDescription, range: range)
            return ToolExecutionResult(
                toolName: SparkToolName.fetchStepDetails,
                outputText: output,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

}
