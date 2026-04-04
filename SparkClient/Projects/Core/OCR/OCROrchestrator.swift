import Foundation
import UIKit

actor OCROrchestrator {
    private let config: OCRConfiguration
    private let visionEngine: OCRTextEngine
    private let aliyunEngine: OCRTextEngine?
    private let localServerEngine: OCRTextEngine?
    private let logger: Logger

    init(
        config: OCRConfiguration,
        visionEngine: OCRTextEngine = VisionOCREngine(),
        aliyunEngine: OCRTextEngine? = nil,
        localServerEngine: OCRTextEngine? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.config = config
        self.visionEngine = visionEngine
        self.aliyunEngine = aliyunEngine
        self.localServerEngine = localServerEngine
        self.logger = logger
    }

    func recognize(image: UIImage, options: OCRRequestOptions = .medicalDefault) async throws -> OCRRecognition {
        guard let imageData = image.jpegData(compressionQuality: 0.98) else {
            throw OCRError.invalidImage
        }
        return try await recognize(imageData: imageData, options: options)
    }

    func recognize(imageData: Data, options: OCRRequestOptions = .medicalDefault) async throws -> OCRRecognition {
        guard let rawImage = UIImage(data: imageData) else {
            throw OCRError.invalidImage
        }

        let workingImage: UIImage
        if options.applyPreprocess {
            workingImage = SparkMedicalImagePreprocessor.shared.preprocess(rawImage)
        } else {
            workingImage = rawImage
        }

        let workingData = workingImage.jpegData(compressionQuality: 0.98) ?? imageData
        let hints = OCRRecognitionHints.from(configuration: config, topCandidatesCount: options.topCandidatesCount)

        async let visionTask: OCRTextOutput? = try? await visionEngine.recognize(imageData: workingData, hints: hints)
        async let aliyunTask: OCRTextOutput? = {
            guard config.enableAliyunOCR, let aliyunEngine else { return nil }
            return try? await aliyunEngine.recognize(imageData: imageData, hints: hints)
        }()
        async let localTask: OCRTextOutput? = {
            guard config.enableLocalServerOCR, let localServerEngine else { return nil }
            return try? await localServerEngine.recognize(imageData: imageData, hints: hints)
        }()

        var outputs: [OCRTextOutput] = []
        if let vision = await visionTask { outputs.append(vision) }
        if let aliyun = await aliyunTask { outputs.append(aliyun) }
        if let local = await localTask { outputs.append(local) }

        guard !outputs.isEmpty else {
            throw OCRError.response("no_ocr_engine_output")
        }

        let best = OCRFusionSelector.selectBest(
            outputs: outputs,
            corrector: SparkMedicalTermsCorrector.shared,
            applyCorrection: options.correctMedicalTerms
        )

        logger.info(
            "OCR completed selected_engine=\(best.selectedEngine) outputs=\(outputs.map { $0.engine }.joined(separator: ",")) text_length=\(best.text.count)",
            category: "ocr"
        )

        return best
    }

    func recognize(document url: URL, options: OCRRequestOptions = .medicalDefault) async throws -> OCRRecognition {
        let extractor = OCRDocumentExtractor(config: config)
        return try await extractor.extractText(from: url, orchestrator: self, options: options)
    }

    func recognize(
        images: [UIImage],
        documents: [URL],
        options: OCRRequestOptions = .medicalDefault,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> OCRRecognition {
        var results: [OCRRecognition] = []
        let total = max(1, images.count + documents.count)
        var done = 0

        for image in images {
            let result = try await recognize(image: image, options: options)
            results.append(result)
            done += 1
            progress?(Double(done) / Double(total))
        }

        for url in documents {
            let result = try await recognize(document: url, options: options)
            results.append(result)
            done += 1
            progress?(Double(done) / Double(total))
        }

        let mergedText = results.map(\.text).joined(separator: "\n")
        let mergedOutputs = results.flatMap(\.outputs)
        let selectedEngine = results.last?.selectedEngine ?? "vision"

        return OCRRecognition(text: mergedText, selectedEngine: selectedEngine, outputs: mergedOutputs)
    }
}
