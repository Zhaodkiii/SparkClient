import Foundation

extension ToolHub {
    func runFetchEnergy(invocation: ToolInvocation) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments)
        let output = healthNoDataDiagnosticIfNeeded(
            await healthTool.fetchEnergyDetails(from: range.start, to: range.end),
            range: range
        )
        return ToolExecutionResult(
            toolName: SparkToolName.fetchEnergyDetails,
            outputText: output,
            sensitive: healthOutputContainsUserData(output),
            shouldBypassModel: true
        )
    }


}
