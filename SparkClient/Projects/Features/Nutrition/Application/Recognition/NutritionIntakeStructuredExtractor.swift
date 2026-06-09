import Foundation

struct NutritionIntakeStructuredExtractor: Sendable {
    let runtimeService: any AIRuntimeServing
    let configCenter: AIConfigCenter
    let promptFactory: any NutritionPromptBuilding
    let jsonNormalizer: MedicalDocumentModelJSONNormalizer
    let logger: Logger

    private let logModule = LogModule.nutrition

    func extractDraft(
        input: NutritionIntakeExtractionInput,
        imageFileIDs: [Int],
        foodDescription: String?,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> NutritionIntakeExtractionResult {
        try cancellationToken?.checkCancellation()
        try await ensureExtractionModelAvailable()

        let startedAt = Date()
        var retryCount = 0
        var retryFeedback: NutritionExtractionRetryFeedback?

        while retryCount <= 1 {
            try cancellationToken?.checkCancellation()
            let promptInput = NutritionIntakeExtractionInput(
                memberID: input.memberID,
                mealType: input.mealType,
                source: input.source,
                text: input.text,
                recognitionID: input.recognitionID,
                retryFeedback: retryFeedback
            )
            let prompt = promptFactory.intakeExtractionPrompt(input: promptInput)
            let final = try await runExtraction(
                prompt: prompt,
                cancellationToken: cancellationToken
            )

            if let decoded = final.decoded {
                let resolved = try await configCenter.resolve(for: .nutritionIntakeExtraction)
                let draft = NutritionRecognitionMapper.mapDraft(
                    decoded,
                    recognitionID: input.recognitionID,
                    source: input.source,
                    mealType: input.mealType,
                    imageFileIDs: imageFileIDs,
                    foodDescription: foodDescription ?? decoded.foodDescription
                )
                let cost = Date().timeIntervalSince(startedAt)
                logger.info(
                    "营养抽取成功 recognitionID=\(input.recognitionID) memberID=\(input.memberID) inputLen=\(input.text.count) items=\(draft.items.count) retry=\(retryCount) model=\(resolved.model) cost=\(String(format: "%.3f", cost))s",
                    module: logModule
                )
                return NutritionIntakeExtractionResult(
                    recognitionID: input.recognitionID,
                    draft: draft,
                    foodDescription: foodDescription ?? decoded.foodDescription,
                    modelName: resolved.model,
                    durationSeconds: cost,
                    retryCount: retryCount
                )
            }

            retryCount += 1
            let preview = truncatedPreview(final.normalizedJSON)
            logger.warning(
                "营养抽取 JSON 解码失败 recognitionID=\(input.recognitionID) retry=\(retryCount) preview=\(LogMessageSanitizer.singleLineSnippet(preview))",
                module: logModule
            )
            if retryCount > 1 {
                throw NutritionRecognitionError.decodingFailed(retryCount: retryCount - 1)
            }
            retryFeedback = NutritionExtractionRetryFeedback(
                errorSummary: final.lastDecodingError?.localizedDescription ?? "invalid_json",
                outputPreview: preview
            )
        }

        throw NutritionRecognitionError.decodingFailed(retryCount: 1)
    }

    func ensureExtractionModelAvailable() async throws {
        let bundles = try await configCenter.effectiveScenarioBundles()
        guard bundles.resolveRow(for: .nutritionIntakeExtraction, preferredModelName: nil) != nil else {
            throw NutritionRecognitionError.intakeExtractionModelUnavailable
        }
    }

    private func runExtraction(
        prompt: String,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> StructuredJSONStreamFinal<NutritionRecognitionDraftResponse> {
        let stream = try await runtimeService.generateTextStream(
            request: AIRuntimeTextRequest(
                scenario: .nutritionIntakeExtraction,
                messages: [AIRuntimeMessage(role: .user, content: prompt)],
                reasoning: .disabled,
                cancellationToken: cancellationToken
            )
        )
        let decoder = StructuredJSONStreamDecoder<NutritionRecognitionDraftResponse>(
            normalizer: jsonNormalizer,
            logger: logger,
            kindLabel: "nutrition_intake_extraction"
        )
        return try await decoder.collect(from: stream, cancellationToken: cancellationToken)
    }

    private func truncatedPreview(_ text: String, limit: Int = 800) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<end])
    }
}
