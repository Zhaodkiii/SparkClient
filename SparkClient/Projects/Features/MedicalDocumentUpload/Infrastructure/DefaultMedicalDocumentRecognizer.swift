import Foundation
import UniformTypeIdentifiers

enum MedicalDocumentRecognizerError: LocalizedError {
    case emptyFiles

    var errorDescription: String? {
        switch self {
        case .emptyFiles:
            return "请先选择文件。"
        }
    }
}

struct DefaultMedicalDocumentRecognizer: MedicalDocumentRecognizer, Sendable {
    let ocrOrchestrator: OCROrchestrator
    let runtimeService: any AIRuntimeServing
    let promptBuilder: any MedicalPromptBuilding
    let logger: Logger

    init(
        ocrOrchestrator: OCROrchestrator,
        runtimeService: any AIRuntimeServing,
        promptBuilder: any MedicalPromptBuilding,
        logger: Logger = ConsoleLogger()
    ) {
        self.ocrOrchestrator = ocrOrchestrator
        self.runtimeService = runtimeService
        self.promptBuilder = promptBuilder
        self.logger = logger
    }

    func recognize(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        mode: MedicalDocumentUploadMode?
    ) async throws -> MedicalDocumentRecognitionResult {
        guard files.isEmpty == false else {
            throw MedicalDocumentRecognizerError.emptyFiles
        }
        logger.info(
            "开始医疗文档识别，memberID=\(memberID), fileCount=\(files.count), mode=\(mode?.rawValue ?? "general")",
            category: "medical_upload"
        )

        let rawText = try await buildMergedOCRText(files: files)
        let prompt = promptBuilder.extractionPrompt(
            for: MedicalPromptInput(mode: mode, mergedOCRText: rawText)
        )
        let response = try await runtimeService.generateText(
            request: AIRuntimeTextRequest(
                scenario: .medicalStructuredExtraction,
                messages: [AIRuntimeMessage(role: .user, content: prompt)]
            )
        )
        let extractedJSON = normalizeJSONEnvelope(response.text)
        let summary = extractedJSON.count > 300 ? String(extractedJSON.prefix(300)) + "..." : extractedJSON

        let result = MedicalDocumentRecognitionResult(
            memberID: memberID,
            requestedMode: mode,
            resolvedMode: mode ?? .general,
            rawOCRText: rawText,
            extractedJSONString: extractedJSON,
            extractedSummary: summary,
            serverPayloadPreview: buildPayloadPreview(memberID: memberID, json: extractedJSON, rawText: rawText)
        )
        logger.info(
            "医疗文档识别成功，ocrLength=\(rawText.count), jsonLength=\(extractedJSON.count)",
            category: "medical_upload"
        )
        return result
    }

    private func buildMergedOCRText(files: [MedicalUploadLocalFile]) async throws -> String {
        // 多文件识别时加分隔头，便于后续模型区分来源，降低跨文件信息串扰风险。
        var chunks: [String] = []
        for (index, file) in files.enumerated() {
            let ocr = try await recognize(file: file)
            let header = "=== File \(index + 1): \(file.displayName) ==="
            chunks.append([header, ocr.text].joined(separator: "\n"))
        }
        return chunks.joined(separator: "\n\n")
    }

    private func recognize(file: MedicalUploadLocalFile) async throws -> OCRRecognition {
        if isImage(url: file.url, mimeType: file.mimeType) {
            logger.info("执行图片 OCR：\(file.displayName)", category: "medical_upload")
            let data = try Data(contentsOf: file.url)
            return try await ocrOrchestrator.recognize(imageData: data, options: .medicalDefault)
        }
        logger.info("执行文档 OCR：\(file.displayName)", category: "medical_upload")
        return try await ocrOrchestrator.recognize(document: file.url, options: .medicalDefault)
    }

    private func isImage(url: URL, mimeType: String?) -> Bool {
        if let mimeType, let type = UTType(mimeType: mimeType), type.conforms(to: .image) {
            return true
        }
        if let extType = UTType(filenameExtension: url.pathExtension), extType.conforms(to: .image) {
            return true
        }
        return false
    }

    private func normalizeJSONEnvelope(_ text: String) -> String {
        text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildPayloadPreview(memberID: Int, json: String, rawText: String) -> String {
        let payload: [String: String] = [
            "memberID": "\(memberID)",
            "extractedJSON": json,
            "rawOCRText": rawText
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let pretty = String(data: data, encoding: .utf8) else {
            logger.warning("构造 payload 预览失败，使用文本回退。", category: "medical_upload")
            return "{\"memberID\":\(memberID),\"extractedJSON\":\(json)}"
        }
        return pretty
    }
}
