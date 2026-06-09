import Foundation

struct NutritionFoodImageDescriber: Sendable {
    let runtimeService: any AIRuntimeServing
    let configCenter: AIConfigCenter
    let promptFactory: any NutritionPromptBuilding
    let logger: Logger

    private let logModule = LogModule.nutrition

    func describeFood(
        input: NutritionPhotoRecognitionInput,
        recognitionID: String,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> NutritionFoodDescriptionResult {
        try cancellationToken?.checkCancellation()
        try await ensureVisualModelAvailable()

        let startedAt = Date()
        let prompt = promptFactory.foodDescriptionPrompt(mealType: input.mealType)
        let jpegBase64 = input.imageJPEGData.base64EncodedString()
        let stream = try await runtimeService.generateTextStream(
            request: AIRuntimeTextRequest(
                scenario: .optimizationVisual,
                messages: [
                    AIRuntimeMessage(
                        role: .user,
                        content: nil,
                        contentParts: [
                            .textPart(prompt),
                            .imageInlineJPEGBase64(jpegBase64)
                        ]
                    )
                ],
                reasoning: .disabled,
                cancellationToken: cancellationToken
            )
        )

        let text = try await collectText(from: stream, cancellationToken: cancellationToken)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw NutritionRecognitionError.emptyDescription
        }

        let resolved = try await configCenter.resolve(for: .optimizationVisual)
        let cost = Date().timeIntervalSince(startedAt)
        logger.info(
            "食物图片描述完成 recognitionID=\(recognitionID) memberID=\(input.memberID) mealType=\(input.mealType.rawValue) model=\(resolved.model) descLen=\(trimmed.count) cost=\(String(format: "%.3f", cost))s",
            module: logModule
        )
        return NutritionFoodDescriptionResult(
            recognitionID: recognitionID,
            descriptionText: trimmed,
            modelName: resolved.model,
            durationSeconds: cost
        )
    }

    func ensureVisualModelAvailable() async throws {
        let bundles = try await configCenter.effectiveScenarioBundles()
        guard let row = bundles.resolveRow(for: .optimizationVisual, preferredModelName: nil) else {
            throw NutritionRecognitionError.visualModelUnavailable
        }
        guard row.supportsMultimodal else {
            throw NutritionRecognitionError.visualModelUnavailable
        }
    }

    private func collectText(
        from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> String {
        var rawText = ""
        var fallback = ""
        for try await event in stream {
            try cancellationToken?.checkCancellation()
            switch event {
            case .textDelta(let delta):
                rawText.append(delta)
            case .completed(let response):
                fallback = response.text
            case .reasoningDelta, .toolCallDelta:
                continue
            }
        }
        if rawText.isEmpty {
            rawText = fallback
        }
        return rawText
    }
}
