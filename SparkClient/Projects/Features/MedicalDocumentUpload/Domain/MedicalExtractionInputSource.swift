import Foundation
import UniformTypeIdentifiers

/// Client-side extraction input for the medical structured-extract AI call.
enum MedicalExtractionInputSource: Sendable, Equatable {
    case ocrText(String)
    case visionImages([MedicalExtractionVisionImage])

    var logLabel: String {
        switch self {
        case .ocrText:
            return "ocr_text"
        case .visionImages:
            return "vision_images"
        }
    }
}

struct MedicalExtractionVisionImage: Sendable, Equatable {
    let fileID: UUID
    let displayName: String
    let mimeType: String
    let originalByteCount: Int
    let compressedJPEGData: Data
}

enum MedicalExtractionPromptSource: Sendable {
    case ocrText
    case visionImage
}

enum MedicalUploadFileKindClassifier {
    static func allFilesAreImages(_ files: [MedicalUploadLocalFile]) -> Bool {
        guard files.isEmpty == false else { return false }
        return files.allSatisfy { isImageFile($0) }
    }

    static func isImageFile(_ file: MedicalUploadLocalFile) -> Bool {
        isImage(url: file.url, mimeType: file.mimeType)
    }

    static func firstNonImageFile(in files: [MedicalUploadLocalFile]) -> MedicalUploadLocalFile? {
        files.first { isImageFile($0) == false }
    }

    static func isImage(url: URL, mimeType: String?) -> Bool {
        if let mimeType, let type = UTType(mimeType: mimeType), type.conforms(to: .image) {
            return true
        }
        if let extType = UTType(filenameExtension: url.pathExtension), extType.conforms(to: .image) {
            return true
        }
        return false
    }
}

struct MedicalExtractionVisionImageBuilder: Sendable {
    static let maxImageCount = 6
    static let maxTotalCompressedBytes = 8 * 1_048_576

    let logger: Logger

    func buildVisionImages(from files: [MedicalUploadLocalFile]) -> [MedicalExtractionVisionImage]? {
        guard files.count <= Self.maxImageCount else { return nil }

        var images: [MedicalExtractionVisionImage] = []
        var totalCompressedBytes = 0

        for file in files {
            guard let originalData = try? Data(contentsOf: file.url) else {
                logger.warning(
                    "医疗抽取回退 OCR：图片读取失败 file=\(safeLogName(file.displayName)) mime=\(file.mimeType ?? "unknown")",
                    module: .medical
                )
                return nil
            }

            guard let compressed = AIImageCompressor.compressForAI(imageData: originalData) else {
                logger.warning(
                    "医疗抽取回退 OCR：图片压缩失败 file=\(safeLogName(file.displayName)) mime=\(file.mimeType ?? "unknown")",
                    module: .medical
                )
                return nil
            }

            totalCompressedBytes += compressed.count
            if totalCompressedBytes > Self.maxTotalCompressedBytes {
                logger.warning(
                    "医疗抽取回退 OCR：图片数量或体积超过限制 imageCount=\(files.count) totalCompressedBytes=\(totalCompressedBytes)",
                    module: .medical
                )
                return nil
            }

            images.append(
                MedicalExtractionVisionImage(
                    fileID: file.id,
                    displayName: file.displayName,
                    mimeType: file.mimeType ?? "image/jpeg",
                    originalByteCount: originalData.count,
                    compressedJPEGData: compressed
                )
            )
        }

        return images.isEmpty ? nil : images
    }

    private func safeLogName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 64 else { return trimmed.isEmpty ? "unnamed" : trimmed }
        return String(trimmed.prefix(64)) + "…"
    }
}

struct MedicalExtractionInputSourceResolver: Sendable {
    static let maxImageCount = MedicalExtractionVisionImageBuilder.maxImageCount

    let logger: Logger
    private let imageBuilder: MedicalExtractionVisionImageBuilder

    init(logger: Logger = ConsoleLogger()) {
        self.logger = logger
        self.imageBuilder = MedicalExtractionVisionImageBuilder(logger: logger)
    }

    func resolve(
        files: [MedicalUploadLocalFile],
        mergedOCRText: String,
        kind: MedicalDocumentKind,
        scenario: AIScenario,
        preferredModelName: String?,
        bundles: AIScenarioRemoteBundlesCollection
    ) -> MedicalExtractionInputSource {
        logger.info(
            "医疗抽取输入源决策开始 kind=\(kind.rawValue) scenario=\(scenario.rawValue) files=\(files.count) preferredModel=\(preferredModelName ?? "nil")",
            module: .medical
        )

        guard MedicalUploadFileKindClassifier.allFilesAreImages(files) else {
            if let nonImage = MedicalUploadFileKindClassifier.firstNonImageFile(in: files) {
                logger.info(
                    "医疗抽取回退 OCR：包含非图片文件 kind=\(kind.rawValue) nonImageCount=1 firstNonImageMime=\(nonImage.mimeType ?? "unknown")",
                    module: .medical
                )
            }
            return .ocrText(mergedOCRText)
        }

        guard files.count <= Self.maxImageCount else {
            logger.info(
                "医疗抽取回退 OCR：图片数量或体积超过限制 imageCount=\(files.count) totalCompressedBytes=0",
                module: .medical
            )
            return .ocrText(mergedOCRText)
        }

        let capabilities = bundles.medicalMultimodalCapabilities(
            for: scenario,
            preferredModelName: preferredModelName
        )
        guard capabilities.supportsMultimodal else {
            logger.info(
                "医疗抽取回退 OCR：当前模型不支持多模态 kind=\(kind.rawValue) scenario=\(scenario.rawValue) model=\(capabilities.modelName ?? "unknown")",
                module: .medical
            )
            return .ocrText(mergedOCRText)
        }

        guard let visionImages = imageBuilder.buildVisionImages(from: files) else {
            return .ocrText(mergedOCRText)
        }

        let totalOriginalBytes = visionImages.reduce(0) { $0 + $1.originalByteCount }
        let totalCompressedBytes = visionImages.reduce(0) { $0 + $1.compressedJPEGData.count }
        logger.info(
            "医疗抽取使用图片多模态 kind=\(kind.rawValue) model=\(capabilities.modelName ?? "unknown") imageCount=\(visionImages.count) totalOriginalBytes=\(totalOriginalBytes) totalCompressedBytes=\(totalCompressedBytes)",
            module: .medical
        )
        return .visionImages(visionImages)
    }
}
