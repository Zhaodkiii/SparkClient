import Foundation

struct MedicalExtractionRetrySettingsStore: Sendable {
    private enum Keys {
        static let enabled = "medicalExtraction.autoRetryOnDecodingFailure.enabled"
        static let maxCount = "medicalExtraction.autoRetryOnDecodingFailure.maxCount"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> MedicalExtractionRetrySettings {
        let hasEnabled = defaults.object(forKey: Keys.enabled) != nil
        let enabled = hasEnabled ? defaults.bool(forKey: Keys.enabled) : false
        let maxCount = defaults.object(forKey: Keys.maxCount) as? Int ?? MedicalExtractionRetrySettings.default.maxDecodingFailureAutoRetryCount
        return MedicalExtractionRetrySettings(
            autoRetryOnDecodingFailureEnabled: enabled,
            maxDecodingFailureAutoRetryCount: maxCount
        ).clamped()
    }

    func save(_ settings: MedicalExtractionRetrySettings) {
        let clamped = settings.clamped()
        defaults.set(clamped.autoRetryOnDecodingFailureEnabled, forKey: Keys.enabled)
        defaults.set(clamped.maxDecodingFailureAutoRetryCount, forKey: Keys.maxCount)
    }
}
