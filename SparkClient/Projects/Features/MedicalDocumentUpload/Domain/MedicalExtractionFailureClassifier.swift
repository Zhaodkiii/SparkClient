import Foundation

enum MedicalExtractionFailureClassifier {
    static func isDecodingFailure(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if error is StructuredJSONDecodingFailure {
            return true
        }
        if error is DecodingError {
            return true
        }
        if let extraction = error as? ExtractionError {
            switch extraction {
            case .decodingFailed:
                return true
            case .invalidDebugPayload:
                return false
            }
        }
        return false
    }
}
