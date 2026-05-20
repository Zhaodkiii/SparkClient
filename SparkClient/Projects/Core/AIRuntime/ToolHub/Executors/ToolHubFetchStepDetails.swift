import Foundation

extension ToolHub {
    func runFetchSteps(invocation: ToolInvocation) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments)
        let output = await healthTool.fetchStepDetails(from: range.start, to: range.end)
        return ToolExecutionResult(
            toolName: SparkToolName.fetchStepDetails,
            outputText: healthNoDataDiagnosticIfNeeded(output, range: range),
            sensitive: true,
            shouldBypassModel: true
        )
    }

}
