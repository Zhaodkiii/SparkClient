#if canImport(XCTest)
import XCTest
@testable import SparkClient

final class MedicalExtractionInputSourceTests: XCTestCase {
    private let resolver = MedicalExtractionInputSourceResolver(logger: ConsoleLogger())
    private let ocrText = "sample ocr text for tests"

    func testAllFilesAreImagesAcceptsJPEGPNGHEIC() {
        let files = [
            makeFile(name: "a.jpg", mime: "image/jpeg"),
            makeFile(name: "b.png", mime: "image/png"),
            makeFile(name: "c.heic", mime: "image/heic")
        ]
        XCTAssertTrue(MedicalUploadFileKindClassifier.allFilesAreImages(files))
    }

    func testAllFilesAreImagesRejectsPDF() {
        let files = [makeFile(name: "report.pdf", mime: "application/pdf")]
        XCTAssertFalse(MedicalUploadFileKindClassifier.allFilesAreImages(files))
    }

    func testAllFilesAreImagesRejectsMixedUpload() {
        let files = [
            makeFile(name: "photo.jpg", mime: "image/jpeg"),
            makeFile(name: "report.pdf", mime: "application/pdf")
        ]
        XCTAssertFalse(MedicalUploadFileKindClassifier.allFilesAreImages(files))
    }

    func testResolveExtractionInputSourceUsesVisionWhenMultimodalAndAllImages() throws {
        let bundles = makeBundles(defaultMultimodal: true)
        let file = try makeTemporaryImageFile(name: "lab.jpg", mime: "image/jpeg")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let source = resolver.resolve(
            files: [file],
            mergedOCRText: ocrText,
            kind: .medicalReport,
            scenario: .medicalReportExtraction,
            preferredModelName: "vision-model",
            bundles: bundles
        )

        guard case .visionImages(let images) = source else {
            return XCTFail("expected vision images")
        }
        XCTAssertEqual(images.count, 1)
        XCTAssertFalse(images[0].compressedJPEGData.isEmpty)
    }

    func testResolveExtractionInputSourceFallsBackWhenModelNotMultimodal() throws {
        let bundles = makeBundles(defaultMultimodal: false)
        let file = try makeTemporaryImageFile(name: "lab.jpg", mime: "image/jpeg")
        defer { try? FileManager.default.removeItem(at: file.url) }

        let source = resolver.resolve(
            files: [file],
            mergedOCRText: ocrText,
            kind: .prescription,
            scenario: .prescriptionExtraction,
            preferredModelName: "text-model",
            bundles: bundles
        )

        guard case .ocrText(let text) = source else {
            return XCTFail("expected ocr text fallback")
        }
        XCTAssertEqual(text, ocrText)
    }

    func testResolveExtractionInputSourceFallsBackForPDF() {
        let bundles = makeBundles(defaultMultimodal: true)
        let files = [makeFile(name: "report.pdf", mime: "application/pdf")]

        let source = resolver.resolve(
            files: files,
            mergedOCRText: ocrText,
            kind: .healthExamReport,
            scenario: .healthExamExtraction,
            preferredModelName: "vision-model",
            bundles: bundles
        )

        guard case .ocrText(let text) = source else {
            return XCTFail("expected ocr text fallback")
        }
        XCTAssertEqual(text, ocrText)
    }

    func testVisionPromptDoesNotContainOCRPlaceholder() {
        let localizer = PromptLocalizer(locale: Locale(identifier: "zh-Hans"))
        let prompt = localizer.prescriptionVisionExtractionPrompt()
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("OCR text:"))
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("from OCR text"))
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("OCR文本："))
        XCTAssertFalse(prompt.contains("%@"))
        XCTAssertTrue(prompt.contains("【图片视觉抽取】"))
        XCTAssertTrue(prompt.contains("处方信息抽取"))
    }

    func testLogRedactorStripsInlineImageBase64UnescapedSlash() {
        let sample = #"{"messages":[{"content":[{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,/9j/4AAQSkZJRg=="}}]}]}"#
        let redacted = AIRuntimeRequestLogRedactor.redact(sample)
        XCTAssertFalse(redacted.contains("/9j/4AAQ"))
        XCTAssertTrue(redacted.contains("data:image/jpeg;base64,<image-redacted>"))
    }

    func testLogRedactorStripsInlineImageBase64EscapedSlash() {
        // JSONEncoder encodes "/" as "\/" — this is the real-world case from the gateway log.
        let sample = #"{"messages":[{"content":[{"type":"image_url","image_url":{"url":"data:image\/jpeg;base64,\/9j\/4AAQSkZJRg=="}}]}]}"#
        let redacted = AIRuntimeRequestLogRedactor.redact(sample)
        XCTAssertFalse(redacted.contains("4AAQSkZJRg=="))
        XCTAssertTrue(redacted.contains("<image-redacted>"))
    }

    func testLogRedactorKeepsNonImageContent() {
        let sample = #"{"messages":[{"content":[{"type":"text","text":"hello world"}]}]}"#
        let redacted = AIRuntimeRequestLogRedactor.redact(sample)
        XCTAssertEqual(redacted, sample)
    }

    func testOCRPromptStillContainsProvidedText() {
        let factory = MedicalPromptFactory(localizer: PromptLocalizer(locale: Locale(identifier: "en_US")))
        let prompt = factory.extractionPrompt(
            for: MedicalPromptInput(kind: .medicalReport, mergedOCRText: "LINE-A\nLINE-B"),
            source: .ocrText
        )
        XCTAssertTrue(prompt.contains("LINE-A"))
        XCTAssertTrue(prompt.contains("LINE-B"))
    }

    func testMedicalMultimodalCapabilitiesTreatsLocalModelAsNonMultimodal() {
        let row = AIScenarioRemoteModelRow(
            name: "local-llm",
            displayName: "Local",
            identity: AIModelIdentity.model.rawValue,
            providerID: LocalModelService.localProviderID,
            company: LocalModelService.localCompany,
            endpoint: "",
            supportsSearch: false,
            supportsMultimodal: true,
            supportsReasoning: false,
            supportsToolUse: false,
            supportsVoiceGen: false,
            supportsImageGen: false,
            supportsText: true,
            supportsDeepReasoning: false,
            reasoningControllable: false,
            priceTier: 0,
            source: "custom",
            aiScenarios: [],
            aiToolScenarios: [],
            relatedTaskCodes: [],
            temperature: 0.2,
            maxTokens: 4096,
            localFilename: "model.gguf"
        )
        let bundle = AIScenarioRemoteBundle(defaultModelName: "local-llm", models: [row])
        let bundles = AIScenarioRemoteBundlesCollection.makeForTests(medicalReportExtraction: bundle)
        let capabilities = bundles.medicalMultimodalCapabilities(
            for: .medicalReportExtraction,
            preferredModelName: "local-llm"
        )
        XCTAssertFalse(capabilities.supportsMultimodal)
    }

    private func makeFile(name: String, mime: String) -> MedicalUploadLocalFile {
        MedicalUploadLocalFile(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            displayName: name,
            mimeType: mime,
            ocrText: nil,
            remoteFile: nil
        )
    }

    private func makeTemporaryImageFile(name: String, mime: String) throws -> MedicalUploadLocalFile {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        let pixel: [UInt8] = [
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
            0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
            0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
            0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
            0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
            0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
            0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
            0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
            0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x03, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
            0x7F, 0xFF, 0xD9
        ]
        try Data(pixel).write(to: url)
        return MedicalUploadLocalFile(
            id: UUID(),
            url: url,
            displayName: name,
            mimeType: mime,
            ocrText: nil,
            remoteFile: nil
        )
    }

    private func makeBundles(defaultMultimodal: Bool) -> AIScenarioRemoteBundlesCollection {
        let row = AIScenarioRemoteModelRow(
            name: defaultMultimodal ? "vision-model" : "text-model",
            displayName: defaultMultimodal ? "Vision" : "Text",
            identity: AIModelIdentity.model.rawValue,
            providerID: "OPENAI",
            company: "OPENAI",
            endpoint: "https://example.com/v1/chat/completions",
            supportsSearch: false,
            supportsMultimodal: defaultMultimodal,
            supportsReasoning: false,
            supportsToolUse: false,
            supportsVoiceGen: false,
            supportsImageGen: false,
            supportsText: true,
            supportsDeepReasoning: false,
            reasoningControllable: false,
            priceTier: 0,
            source: "custom",
            aiScenarios: [],
            aiToolScenarios: [],
            relatedTaskCodes: [],
            temperature: 0.2,
            maxTokens: 4096
        )
        let bundle = AIScenarioRemoteBundle(defaultModelName: row.name, models: [row])
        return AIScenarioRemoteBundlesCollection.makeForTests(medicalReportExtraction: bundle)
    }
}

private extension AIScenarioRemoteBundlesCollection {
    static func makeForTests(medicalReportExtraction: AIScenarioRemoteBundle) -> AIScenarioRemoteBundlesCollection {
        let empty = AIScenarioRemoteBundle(defaultModelName: "", models: [])
        return AIScenarioRemoteBundlesCollection(
            chat: empty,
            embedding: empty,
            voice: empty,
            medicalStructuredExtraction: empty,
            medicalDocumentTypeRecognition: empty,
            medicalCaseExtraction: empty,
            healthExamExtraction: empty,
            medicalReportExtraction: medicalReportExtraction,
            prescriptionExtraction: medicalReportExtraction,
            medicationExtraction: empty,
            medicineBoxExtraction: empty,
            optimizationText: empty,
            optimizationVisual: empty,
            contextFolding: empty,
            router: empty,
            modelConfig: empty,
            reportInterpretation: empty,
            nutritionIntakeExtraction: empty
        )
    }
}
#endif
