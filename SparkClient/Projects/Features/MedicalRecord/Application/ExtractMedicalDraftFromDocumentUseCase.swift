import Foundation
import UIKit

struct ExtractMedicalDraftFromDocumentUseCase: Sendable {
    let ocrOrchestrator: OCROrchestrator
    let runtimeService: any AIRuntimeServing
    let draftRepository: any MedicalDraftRepository
    let logger: Logger

    init(
        ocrOrchestrator: OCROrchestrator,
        runtimeService: any AIRuntimeServing,
        draftRepository: any MedicalDraftRepository,
        logger: Logger = ConsoleLogger()
    ) {
        self.ocrOrchestrator = ocrOrchestrator
        self.runtimeService = runtimeService
        self.draftRepository = draftRepository
        self.logger = logger
    }

    func execute(patientID: UUID, filePath: String) async throws -> RecognizedMedicalDraft {
        let fileURL = URL(fileURLWithPath: filePath)
        let ocr = try await recognize(fileURL: fileURL)

        let draft = await buildDraft(
            patientID: patientID,
            sourcePath: filePath,
            rawText: ocr.text
        )
        await draftRepository.save(draft)
        logger.info("病历草稿已生成，patient=\(patientID), source=\(filePath)", category: "medical_draft")
        return draft
    }

    private func recognize(fileURL: URL) async throws -> OCRRecognition {
        let ext = fileURL.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "heif", "webp"].contains(ext) {
            let data = try Data(contentsOf: fileURL)
            return try await ocrOrchestrator.recognize(imageData: data, options: .medicalDefault)
        }
        return try await ocrOrchestrator.recognize(document: fileURL, options: .medicalDefault)
    }

    private func buildDraft(
        patientID: UUID,
        sourcePath: String,
        rawText: String
    ) async -> RecognizedMedicalDraft {
        let extracted = await extractByAI(rawText: rawText) ?? extractByHeuristic(rawText: rawText)
        return RecognizedMedicalDraft(
            patientID: patientID,
            sourcePath: sourcePath,
            rawText: rawText,
            title: extracted.title,
            summary: extracted.summary,
            diagnosis: extracted.diagnosis,
            occurredAt: extracted.occurredAt
        )
    }

    private func extractByAI(rawText: String) async -> DraftExtractionResult? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let promptLocalizer = PromptLocalizer()

        let prompt = promptLocalizer.extractionPrompt(ocrText: trimmed)

        do {
            let response = try await runtimeService.generateText(
                request: AIRuntimeTextRequest(
                    scenario: .optimizationText,
                    messages: [
                        AIRuntimeMessage(role: .user, content: prompt)
                    ]
                )
            )
            return parseExtractionResponse(response.text)
        } catch {
            logger.warning("AI 抽取失败，回退规则抽取：\(error.localizedDescription)", category: "medical_draft")
            return nil
        }
    }

    private func parseExtractionResponse(_ text: String) -> DraftExtractionResult? {
        let payload = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payload.data(using: .utf8) else { return nil }

        struct Parsed: Decodable {
            let title: String?
            let summary: String?
            let diagnosis: String?
            let occurredAt: String?
        }

        guard let parsed = try? JSONDecoder().decode(Parsed.self, from: data) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "yyyy-MM-dd"

        let date = parsed.occurredAt.flatMap { formatter.date(from: $0) } ?? Date()
        let title = (parsed.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (parsed.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let diagnosis = parsed.diagnosis?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false || summary.isEmpty == false else { return nil }

        return DraftExtractionResult(
            title: title.isEmpty ? PromptLocalizer().extractionFallbackTitle() : title,
            summary: summary.isEmpty ? PromptLocalizer().extractionFallbackSummary() : summary,
            diagnosis: diagnosis,
            occurredAt: date
        )
    }

    private func extractByHeuristic(rawText: String) -> DraftExtractionResult {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = normalized
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let promptLocalizer = PromptLocalizer()

        let title = lines.first ?? promptLocalizer.extractionFallbackTitle()
        let summary = String(normalized.prefix(120))
        let diagnosisLine = lines.first { line in
            line.contains("诊断") || line.lowercased().contains("diagnosis")
        }
        let diagnosis = diagnosisLine?.replacingOccurrences(of: "诊断", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return DraftExtractionResult(
            title: title,
            summary: summary.isEmpty ? promptLocalizer.extractionFallbackSummary() : summary,
            diagnosis: diagnosis,
            occurredAt: Date()
        )
    }
}

private struct DraftExtractionResult: Sendable {
    let title: String
    let summary: String
    let diagnosis: String?
    let occurredAt: Date
}
