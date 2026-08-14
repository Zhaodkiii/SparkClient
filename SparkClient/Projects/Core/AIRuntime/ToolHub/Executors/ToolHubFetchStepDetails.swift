import Foundation

extension ToolHub {
    func runFetchSteps(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
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
