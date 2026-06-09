import Foundation

protocol NutritionPromptBuilding: Sendable {
    func foodDescriptionPrompt(mealType: NutritionMealType) -> String
    func intakeExtractionPrompt(input: NutritionIntakeExtractionInput) -> String
}

struct NutritionPromptFactory: NutritionPromptBuilding {
    private let localizer: PromptLocalizer

    init(localizer: PromptLocalizer = PromptLocalizer()) {
        self.localizer = localizer
    }

    func foodDescriptionPrompt(mealType: NutritionMealType) -> String {
        localizer.nutritionFoodDescriptionPrompt(mealType: mealType)
    }

    func intakeExtractionPrompt(input: NutritionIntakeExtractionInput) -> String {
        let base = localizer.nutritionIntakeExtractionPrompt(
            mealType: input.mealType,
            sourceText: input.text
        )
        guard let feedback = input.retryFeedback else { return base }
        let correction = localizer.nutritionExtractionRetryCorrectionPrompt(
            errorSummary: feedback.errorSummary,
            outputPreview: feedback.outputPreview
        )
        return [base, correction]
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .joined(separator: "\n\n---\n\n")
    }
}
