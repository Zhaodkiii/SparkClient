import Foundation

extension ToolHub {
    func runFetchEnergy(invocation: ToolInvocation) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments)
        let output = await healthTool.fetchEnergyDetails(from: range.start, to: range.end)
        return ToolExecutionResult(
            toolName: SparkToolName.fetchEnergyDetails,
            outputText: healthNoDataDiagnosticIfNeeded(output, range: range),
            sensitive: true,
            shouldBypassModel: true
        )
    }


}
