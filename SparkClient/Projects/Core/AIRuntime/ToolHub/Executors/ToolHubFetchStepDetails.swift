import Foundation

extension ToolHub {
    func runFetchSteps(invocation: ToolInvocation) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments)
        return ToolExecutionResult(
            toolName: SparkToolName.fetchStepDetails,
            outputText: await healthTool.fetchStepDetails(from: range.start, to: range.end),
            sensitive: true,
            shouldBypassModel: true
        )
    }

}
