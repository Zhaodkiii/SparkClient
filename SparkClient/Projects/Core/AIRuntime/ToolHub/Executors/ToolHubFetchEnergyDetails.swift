import Foundation

extension ToolHub {
    func runFetchEnergy(invocation: ToolInvocation) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments)
        return ToolExecutionResult(
            toolName: SparkToolName.fetchEnergyDetails,
            outputText: await healthTool.fetchEnergyDetails(from: range.start, to: range.end),
            sensitive: true,
            shouldBypassModel: true
        )
    }


}
