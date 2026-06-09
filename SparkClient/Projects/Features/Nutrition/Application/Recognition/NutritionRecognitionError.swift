import Foundation

enum NutritionRecognitionError: Error, Equatable, Sendable {
    case visualModelUnavailable
    case intakeExtractionModelUnavailable
    case cancelled
    case emptyInput
    case emptyDescription
    case decodingFailed(retryCount: Int)
    case aiServiceFailed(messageKey: String)
}

extension NutritionRecognitionError {
    var localizationKey: String {
        switch self {
        case .visualModelUnavailable:
            return "nutrition.recognition.error.visual_model_unavailable"
        case .intakeExtractionModelUnavailable:
            return "nutrition.recognition.error.extraction_model_unavailable"
        case .cancelled:
            return "nutrition.recognition.error.cancelled"
        case .emptyInput:
            return "nutrition.recognition.error.empty_input"
        case .emptyDescription:
            return "nutrition.recognition.error.empty_description"
        case .decodingFailed:
            return "nutrition.recognition.error.decoding_failed"
        case .aiServiceFailed(let messageKey):
            return messageKey
        }
    }
}
