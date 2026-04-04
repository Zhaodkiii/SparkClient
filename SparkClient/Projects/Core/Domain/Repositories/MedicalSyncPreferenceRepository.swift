import Foundation

enum CloudSyncPriority: String, Codable, CaseIterable, Equatable, Sendable {
    case realtime
    case balanced
    case background
}

struct MedicalSyncPreference: Codable, Equatable, Sendable {
    var isSyncEnabled: Bool
    var hasCompletedInitialUpload: Bool
    var lastSyncAt: Date?
    var syncPriority: CloudSyncPriority

    static let `default` = MedicalSyncPreference(
        isSyncEnabled: true,
        hasCompletedInitialUpload: false,
        lastSyncAt: nil,
        syncPriority: .balanced
    )

    enum CodingKeys: String, CodingKey {
        case isSyncEnabled
        case hasCompletedInitialUpload
        case lastSyncAt
        case syncPriority
    }

    init(
        isSyncEnabled: Bool,
        hasCompletedInitialUpload: Bool,
        lastSyncAt: Date?,
        syncPriority: CloudSyncPriority
    ) {
        self.isSyncEnabled = isSyncEnabled
        self.hasCompletedInitialUpload = hasCompletedInitialUpload
        self.lastSyncAt = lastSyncAt
        self.syncPriority = syncPriority
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isSyncEnabled = (try? container.decode(Bool.self, forKey: .isSyncEnabled)) ?? true
        self.hasCompletedInitialUpload = (try? container.decode(Bool.self, forKey: .hasCompletedInitialUpload)) ?? false
        self.lastSyncAt = try? container.decode(Date.self, forKey: .lastSyncAt)
        self.syncPriority = (try? container.decode(CloudSyncPriority.self, forKey: .syncPriority)) ?? .balanced
    }
}

protocol MedicalSyncPreferenceRepository: Sendable {
    func loadPreference() async -> MedicalSyncPreference
    func savePreference(_ preference: MedicalSyncPreference) async
}
