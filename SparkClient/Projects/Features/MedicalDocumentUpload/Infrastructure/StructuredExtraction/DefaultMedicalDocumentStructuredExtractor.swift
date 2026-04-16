import Foundation

enum ExtractionError: Error {
    case decodingFailed
    case invalidDebugPayload
}

struct DefaultMedicalDocumentStructuredExtractor: MedicalDocumentStructuredExtracting, Sendable {
    let promptFactory: any MedicalPromptBuilding
    let runtimeService: any AIRuntimeServing
    let logger: Logger
    let jsonNormalizer: MedicalDocumentModelJSONNormalizer

    init(
        promptFactory: any MedicalPromptBuilding,
        runtimeService: any AIRuntimeServing,
        logger: Logger = ConsoleLogger(),
        jsonNormalizer: MedicalDocumentModelJSONNormalizer = .init()
    ) {
        self.promptFactory = promptFactory
        self.runtimeService = runtimeService
        self.logger = logger
        self.jsonNormalizer = jsonNormalizer
    }

    func extract(
        kind: MedicalDocumentKind,
        mergedOCRText: String
    ) async throws -> MedicalDocumentStructuredExtractionOutput {
        let prompt = promptFactory.extractionPrompt(
            for: MedicalPromptInput(kind: kind, mergedOCRText: mergedOCRText)
        )
        let final = try await extractTypedResult(kind: kind, prompt: prompt)
        return MedicalDocumentStructuredExtractionOutput(
            typedResult: final.typed,
            extractedJSON: final.json
        )
    }

    private func extractTypedResult(
        kind: MedicalDocumentKind,
        prompt: String
    ) async throws -> (typed: MedicalDocumentTypedResult, json: String) {
        switch kind {
        case .caseDocument:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .medicalCaseExtraction,
                kindLabel: "case_document",
                as: CaseRecognitionDraft.self
            )
            guard let draft = final.decoded else { throw ExtractionError.decodingFailed }
            return (.caseDocument(draft), final.normalizedJSON)
        case .healthExamReport:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .healthExamExtraction,
                kindLabel: "health_exam_report",
                as: HealthExamRecognitionDraft.self
            )
            guard let draft = final.decoded else { throw ExtractionError.decodingFailed }
            return (.healthExamReport(draft), final.normalizedJSON)
        case .medicalReport, .auto:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .medicalReportExtraction,
                kindLabel: "medical_report",
                as: [MedicalReportRecognitionDraft].self
            )
            guard let draft = final.decoded else { throw ExtractionError.decodingFailed }
            return (.medicalReport(draft), final.normalizedJSON)
        case .prescription:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .prescriptionExtraction,
                kindLabel: "prescription",
                as: PrescriptionRecognitionDraft.self
            )
            guard let draft = final.decoded else { throw ExtractionError.decodingFailed }
            return (.prescription(draft), final.normalizedJSON)
        case .medication:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .medicationExtraction,
                kindLabel: "medication",
                as: [MedicationRecognitionDraft].self
            )
            guard let draft = final.decoded else { throw ExtractionError.decodingFailed }
            return (.medication(draft), final.normalizedJSON)
        }
    }

    private func extractStructured<T: Decodable>(
        prompt: String,
        scenario: AIScenario,
        kindLabel: String,
        as type: T.Type
    ) async throws -> StructuredJSONStreamFinal<T> {
        let stream = try await runtimeService.generateTextStream(
            request: AIRuntimeTextRequest(
                scenario: scenario,
                messages: [AIRuntimeMessage(role: .user, content: prompt)],
                reasoning: .disabled
            )
        )
        let decoder = StructuredJSONStreamDecoder<T>(
            normalizer: jsonNormalizer,
            logger: logger,
            kindLabel: kindLabel
        )
        let final = try await decoder.collect(from: stream)
        if final.decoded == nil {
            logger.warning("文档 JSON 解码失败，kind=\(kindLabel)", module: .medical)
        } else {
            logger.debug("文档 JSON 解码成功，kind=\(kindLabel)", module: .medical)
        }
        return final
    }
}
