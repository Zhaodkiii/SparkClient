import Foundation

struct MedicalExtractionRetrySettings: Equatable, Codable, Sendable {
    var autoRetryOnDecodingFailureEnabled: Bool
    var maxDecodingFailureAutoRetryCount: Int

    static let `default` = MedicalExtractionRetrySettings(
        autoRetryOnDecodingFailureEnabled: false,
        maxDecodingFailureAutoRetryCount: 1
    )

    func clamped() -> MedicalExtractionRetrySettings {
        var next = self
        next.maxDecodingFailureAutoRetryCount = min(max(maxDecodingFailureAutoRetryCount, 1), 5)
        return next
    }
}
