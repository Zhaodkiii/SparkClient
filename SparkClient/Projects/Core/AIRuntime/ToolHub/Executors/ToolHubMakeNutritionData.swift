import Foundation

extension ToolHub {
    func runMakeNutritionData(invocation: ToolInvocation) -> ToolExecutionResult {
        let card = healthTool.makeNutritionData(
            protein: parseDoubleValue(invocation.arguments["protein"]),
            carbohydrates: parseDoubleValue(invocation.arguments["carbohydrates"]),
            fat: parseDoubleValue(invocation.arguments["fat"]),
            energy: parseDoubleValue(invocation.arguments["energy"])
        )
        let json = (try? JSONEncoder.default.encode(card))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "{}"
        return ToolExecutionResult(
            toolName: SparkToolName.makeNutritionData,
            outputText: "nutrition_card=\(json)",
            sensitive: false,
            shouldBypassModel: true
        )
    }


}
