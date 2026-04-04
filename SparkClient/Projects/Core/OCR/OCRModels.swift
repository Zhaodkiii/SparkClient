import Foundation
import Vision

struct OCRRequestOptions: Sendable {
    var preferMedicalPreset: Bool
    var applyPreprocess: Bool
    var correctMedicalTerms: Bool
    var topCandidatesCount: Int
    var useTiling: Bool

    static let medicalDefault = OCRRequestOptions(
        preferMedicalPreset: true,
        applyPreprocess: true,
        correctMedicalTerms: true,
        topCandidatesCount: 3,
        useTiling: false
    )

    static let fastPreview = OCRRequestOptions(
        preferMedicalPreset: false,
        applyPreprocess: false,
        correctMedicalTerms: false,
        topCandidatesCount: 1,
        useTiling: false
    )
}

enum OCRLanguageStrategy: Sendable, Equatable, Codable {
    case system
    case codes([String])

    func resolvedCodes() -> [String] {
        switch self {
        case .system:
            return OCRLanguageStrategy.systemPreferredVisionCodes()
        case let .codes(codes):
            return OCRLanguageStrategy.normalizeVisionCodes(codes)
        }
    }

    private static func systemPreferredVisionCodes() -> [String] {
        let raw = Locale.preferredLanguages
        var out: [String] = []
        for lang in raw {
            if lang.hasPrefix("zh-Hans") { out.append("zh-Hans"); continue }
            if lang.hasPrefix("zh-Hant") { out.append("zh-Hant"); continue }
            if lang.hasPrefix("en") { out.append("en-US"); continue }
            if lang.hasPrefix("ja") { out.append("ja-JP"); continue }
            if lang.hasPrefix("ko") { out.append("ko-KR"); continue }
            out.append(lang)
        }
        return normalizeVisionCodes(out)
    }

    private static func normalizeVisionCodes(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        return codes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

struct OCRConfiguration: Sendable, Equatable, Codable {
    var language: OCRLanguageStrategy
    var recognitionLevelRaw: String
    var useLanguageCorrection: Bool
    var pdfRenderScale: CGFloat
    var thumbnailMaxSide: CGFloat
    var enableAliyunOCR: Bool
    var enableLocalServerOCR: Bool
    var localServerBaseURL: String
    var localServerTimeoutMs: Int
    var localServerAuthToken: String?

    init(
        language: OCRLanguageStrategy = .system,
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        useLanguageCorrection: Bool = false,
        pdfRenderScale: CGFloat = 2.0,
        thumbnailMaxSide: CGFloat = 1600,
        enableAliyunOCR: Bool = false,
        enableLocalServerOCR: Bool = false,
        localServerBaseURL: String = "",
        localServerTimeoutMs: Int = 10_000,
        localServerAuthToken: String? = nil
    ) {
        self.language = language
        self.recognitionLevelRaw = OCRConfiguration.encodeRecognitionLevel(recognitionLevel)
        self.useLanguageCorrection = useLanguageCorrection
        self.pdfRenderScale = pdfRenderScale
        self.thumbnailMaxSide = thumbnailMaxSide
        self.enableAliyunOCR = enableAliyunOCR
        self.enableLocalServerOCR = enableLocalServerOCR
        self.localServerBaseURL = localServerBaseURL
        self.localServerTimeoutMs = localServerTimeoutMs
        self.localServerAuthToken = localServerAuthToken
    }

    var recognitionLevel: VNRequestTextRecognitionLevel {
        OCRConfiguration.decodeRecognitionLevel(recognitionLevelRaw)
    }

    private static func encodeRecognitionLevel(_ level: VNRequestTextRecognitionLevel) -> String {
        level == .accurate ? "accurate" : "fast"
    }

    private static func decodeRecognitionLevel(_ raw: String) -> VNRequestTextRecognitionLevel {
        raw == "fast" ? .fast : .accurate
    }
}

struct OCRRecognitionHints: Sendable {
    let languages: [String]
    let recognitionLevel: VNRequestTextRecognitionLevel
    let topCandidatesCount: Int
    let useLanguageCorrection: Bool

    static func from(configuration: OCRConfiguration, topCandidatesCount: Int) -> OCRRecognitionHints {
        OCRRecognitionHints(
            languages: configuration.language.resolvedCodes(),
            recognitionLevel: configuration.recognitionLevel,
            topCandidatesCount: max(1, topCandidatesCount),
            useLanguageCorrection: configuration.useLanguageCorrection
        )
    }
}

struct OCRTextOutput: Sendable {
    let engine: String
    let text: String
    let confidence: Double?
    let elapsedMs: Int?
}

struct OCRRecognition: Sendable {
    let text: String
    let selectedEngine: String
    let outputs: [OCRTextOutput]
}

enum OCRError: Error, Sendable {
    case invalidImage
    case invalidDocumentURL
    case engineUnavailable(String)
    case transport(String)
    case response(String)
}

protocol OCRTextEngine: Sendable {
    var name: String { get }
    func recognize(imageData: Data, hints: OCRRecognitionHints) async throws -> OCRTextOutput
}

protocol OCRCredentialsProvider: Sendable {
    func fetchAliyunOCRCredentials() async throws -> OCRAliyunCredentials
}

struct OCRAliyunCredentials: Sendable {
    let accessKeyId: String
    let accessKeySecret: String
    let securityToken: String?
}
