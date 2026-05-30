import Foundation

extension ToolHub {
    func runMakeNutritionData(invocation: ToolInvocation, context: ToolExecutionContext) -> ToolExecutionResult {
        let proteinResult = parseValidatedNutrient(invocation.arguments["protein"], max: 1_000)
        let carbohydratesResult = parseValidatedNutrient(invocation.arguments["carbohydrates"], max: 1_000)
        let fatResult = parseValidatedNutrient(invocation.arguments["fat"], max: 1_000)
        let energyResult = parseValidatedNutrient(invocation.arguments["energy"], max: 10_000)

        if let errorMessage = firstNutritionValidationError(
            proteinResult,
            carbohydratesResult,
            fatResult,
            energyResult
        ) {
            return ToolExecutionResult(
                toolName: SparkToolName.makeNutritionData,
                outputText: errorMessage,
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let protein = proteinResult.value
        let carbohydrates = carbohydratesResult.value
        let fat = fatResult.value
        let energy = energyResult.value
        let mealName = trimmedOptional(invocation.arguments["meal_name"])
        let sourceText = trimmedOptional(invocation.arguments["source_text"])

        guard protein != nil || carbohydrates != nil || fat != nil || energy != nil else {
            return ToolExecutionResult(
                toolName: SparkToolName.makeNutritionData,
                outputText: L10n.text(
                    "tool.error.nutrition_card.missing_values",
                    fallback: "营养数据无效：蛋白质、碳水、脂肪、能量不能全部为空。"
                ),
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let card = ChatNutritionCardPayload(
            date: Date(),
            proteinGrams: protein,
            carbohydratesGrams: carbohydrates,
            fatGrams: fat,
            energyKilocalories: energy,
            mealName: mealName,
            sourceText: sourceText
        )

        var sideEffects: [ToolSideEffect] = []
        if context.threadID != nil, context.assistantMessageClientID != nil {
            sideEffects = [.nutritionCards([card])]
        }

        return ToolExecutionResult(
            toolName: SparkToolName.makeNutritionData,
            outputText: L10n.text(
                "tool.result.nutrition_card.generated",
                fallback: "营养卡片已生成，请在消息内确认后写入健康应用。"
            ),
            sensitive: true,
            shouldBypassModel: true,
            sideEffects: sideEffects
        )
    }

    private enum NutritionValueParseResult {
        case absent
        case valid(Double?)
        case invalid

        var value: Double? {
            switch self {
            case .absent, .invalid:
                return nil
            case .valid(let value):
                return value
            }
        }
    }

    private func parseValidatedNutrient(_ text: String?, max: Double) -> NutritionValueParseResult {
        guard let text, trimmedOptional(text) != nil else { return .absent }
        guard let value = parseDoubleValue(text), value.isFinite, value >= 0, value <= max else {
            return .invalid
        }
        return .valid(value)
    }

    private func firstNutritionValidationError(
        _ values: NutritionValueParseResult...
    ) -> String? {
        guard values.contains(where: {
            if case .invalid = $0 { return true }
            return false
        }) else {
            return nil
        }
        return L10n.text(
            "tool.error.nutrition_card.invalid_values",
            fallback: "营养数据无效：数值必须是 0 以上的有限数字，且需在合理范围内。"
        )
    }

    private func trimmedOptional(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
