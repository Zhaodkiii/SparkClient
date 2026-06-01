import Foundation

/// 结构化抽取失败后，继续识别时携带给模型的纠错上下文。
struct MedicalExtractionRetryFeedback: Sendable, Codable, Equatable {
    let kind: MedicalDocumentKind
    let step: MedicalDocumentUploadFlowStep.Kind
    let errorCode: MedicalExtractionRetryErrorCode
    let fieldPath: String?
    let expectedType: String?
    let actualType: String?
    let rawMessage: String
    let aiOutputPreview: String?
    let suggestion: String?
    let createdAt: Date
}

enum MedicalExtractionRetryErrorCode: String, Codable, Sendable {
    case jsonTypeMismatch
    case jsonKeyNotFound
    case jsonValueNotFound
    case jsonDataCorrupted
    case invalidJSONShape
    case markdownWrappedJSON
    case unknown
}
