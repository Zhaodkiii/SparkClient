import Foundation

protocol NutritionRecognitionPipeline: Sendable {
    func recognizeFromPhoto(
        input: NutritionPhotoRecognitionInput,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> NutritionRecognitionResult

    func recognizeFromText(
        input: NutritionTextRecognitionInput,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> NutritionRecognitionResult
}

struct DefaultNutritionRecognitionPipeline: NutritionRecognitionPipeline, Sendable {
    let imageDescriber: NutritionFoodImageDescriber
    let intakeExtractor: NutritionIntakeStructuredExtractor
    let logger: Logger

    private let logModule = LogModule.nutrition

    func recognizeFromPhoto(
        input: NutritionPhotoRecognitionInput,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> NutritionRecognitionResult {
        guard input.imageJPEGData.isEmpty == false else {
            throw NutritionRecognitionError.emptyInput
        }

        let recognitionID = NutritionRecognitionMapper.makeRecognitionID()
        logger.info(
            "拍照识别开始 recognitionID=\(recognitionID) memberID=\(input.memberID) mealType=\(input.mealType.rawValue) fileIDs=\(input.imageFileIDs)",
            module: logModule
        )

        let description = try await imageDescriber.describeFood(
            input: input,
            recognitionID: recognitionID,
            cancellationToken: cancellationToken
        )

        let extraction = try await intakeExtractor.extractDraft(
            input: NutritionIntakeExtractionInput(
                memberID: input.memberID,
                mealType: input.mealType,
                source: .photoAI,
                text: description.descriptionText,
                recognitionID: recognitionID,
                retryFeedback: nil
            ),
            imageFileIDs: input.imageFileIDs,
            foodDescription: description.descriptionText,
            cancellationToken: cancellationToken
        )

        return NutritionRecognitionMapper.toRecognitionResult(
            extraction: extraction,
            source: .photoAI,
            mealType: input.mealType,
            foodDescription: description.descriptionText
        )
    }

    func recognizeFromText(
        input: NutritionTextRecognitionInput,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> NutritionRecognitionResult {
        let trimmed = input.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw NutritionRecognitionError.emptyInput
        }

        let recognitionID = NutritionRecognitionMapper.makeRecognitionID()
        logger.info(
            "自然语言识别开始 recognitionID=\(recognitionID) memberID=\(input.memberID) mealType=\(input.mealType.rawValue) inputLen=\(trimmed.count)",
            module: logModule
        )

        let extraction = try await intakeExtractor.extractDraft(
            input: NutritionIntakeExtractionInput(
                memberID: input.memberID,
                mealType: input.mealType,
                source: .textAI,
                text: trimmed,
                recognitionID: recognitionID,
                retryFeedback: nil
            ),
            imageFileIDs: [],
            foodDescription: nil,
            cancellationToken: cancellationToken
        )

        return NutritionRecognitionMapper.toRecognitionResult(
            extraction: extraction,
            source: .textAI,
            mealType: input.mealType,
            foodDescription: trimmed
        )
    }
}
