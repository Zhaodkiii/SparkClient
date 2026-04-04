import Foundation

final class DefaultMedicalSyncPreferenceRepository: MedicalSyncPreferenceRepository, @unchecked Sendable {
    private enum Keys {
        static let preference = "spark.medical.sync.preference.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadPreference() async -> MedicalSyncPreference {
        guard let data = defaults.data(forKey: Keys.preference),
              let pref = try? decoder.decode(MedicalSyncPreference.self, from: data) else {
            return .default
        }
        return pref
    }

    func savePreference(_ preference: MedicalSyncPreference) async {
        if let data = try? encoder.encode(preference) {
            defaults.set(data, forKey: Keys.preference)
        }
    }
}
