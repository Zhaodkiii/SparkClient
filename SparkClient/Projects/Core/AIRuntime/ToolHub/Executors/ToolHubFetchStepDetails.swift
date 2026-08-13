import Foundation

extension ToolHub {
    func runFetchSteps(invocation: ToolInvocation) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments)
        let output = healthNoDataDiagnosticIfNeeded(
            await healthTool.fetchStepDetails(from: range.start, to: range.end),
            range: range
        )
        return ToolExecutionResult(
            toolName: SparkToolName.fetchStepDetails,
            outputText: output,
            sensitive: healthOutputContainsUserData(output),
            shouldBypassModel: true
        )
    }

}
