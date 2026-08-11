import Foundation

nonisolated struct AutoSmallTaskRegistryRecord: Codable, Equatable, Sendable {
    let userID: Int64
    let businessKey: ChatAutoSmallTaskBusinessKey
    let smallTaskCode: String
    let localSmallTaskID: Int
    let payloadVersion: Int
    let payloadHash: String
    let createdAt: Date
    let updatedAt: Date
}

final class UserDefaultsAutoSmallTaskRegistryStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(userID: Int64, businessKey: ChatAutoSmallTaskBusinessKey) -> AutoSmallTaskRegistryRecord? {
        guard let data = defaults.data(forKey: storageKey(userID: userID, businessKey: businessKey)) else {
            return nil
        }
        return try? decoder.decode(AutoSmallTaskRegistryRecord.self, from: data)
    }

    func save(_ record: AutoSmallTaskRegistryRecord) {
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: storageKey(userID: record.userID, businessKey: record.businessKey))
    }

    private func storageKey(userID: Int64, businessKey: ChatAutoSmallTaskBusinessKey) -> String {
        "chat.autoSmallTask.registry.\(userID).\(businessKey.rawValue)"
    }
}

