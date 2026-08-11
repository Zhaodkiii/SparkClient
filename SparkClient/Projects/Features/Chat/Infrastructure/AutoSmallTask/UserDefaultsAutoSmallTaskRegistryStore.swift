import Foundation

nonisolated struct AutoSmallTaskRegistryRecord: Codable, Equatable, Sendable {
    let userID: Int64
    let businessKey: ChatAutoSmallTaskBusinessKey
    let smallTaskCode: String
    let localSmallTaskID: Int
    let definitionVersion: Int
    let minimumRuntimeVersion: Int
    let toolContractVersion: Int
    let payloadHash: String
    let lastMigrationAction: AutoSmallTaskMigrationAction
    let lastMigrationReason: String
    let createdAt: Date
    let updatedAt: Date

    var payloadVersion: Int { definitionVersion }

    init(
        userID: Int64,
        businessKey: ChatAutoSmallTaskBusinessKey,
        smallTaskCode: String,
        localSmallTaskID: Int,
        definitionVersion: Int,
        minimumRuntimeVersion: Int,
        toolContractVersion: Int,
        payloadHash: String,
        lastMigrationAction: AutoSmallTaskMigrationAction,
        lastMigrationReason: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.userID = userID
        self.businessKey = businessKey
        self.smallTaskCode = smallTaskCode
        self.localSmallTaskID = localSmallTaskID
        self.definitionVersion = definitionVersion
        self.minimumRuntimeVersion = minimumRuntimeVersion
        self.toolContractVersion = toolContractVersion
        self.payloadHash = payloadHash
        self.lastMigrationAction = lastMigrationAction
        self.lastMigrationReason = lastMigrationReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case userID
        case businessKey
        case smallTaskCode
        case localSmallTaskID
        case definitionVersion
        case payloadVersion
        case minimumRuntimeVersion
        case toolContractVersion
        case payloadHash
        case lastMigrationAction
        case lastMigrationReason
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(Int64.self, forKey: .userID)
        businessKey = try c.decode(ChatAutoSmallTaskBusinessKey.self, forKey: .businessKey)
        smallTaskCode = try c.decode(String.self, forKey: .smallTaskCode)
        localSmallTaskID = try c.decode(Int.self, forKey: .localSmallTaskID)
        definitionVersion = try c.decodeIfPresent(Int.self, forKey: .definitionVersion)
            ?? c.decodeIfPresent(Int.self, forKey: .payloadVersion)
            ?? 1
        minimumRuntimeVersion = try c.decodeIfPresent(Int.self, forKey: .minimumRuntimeVersion)
            ?? AutoSmallTaskRuntimeVersion.current
        toolContractVersion = try c.decodeIfPresent(Int.self, forKey: .toolContractVersion)
            ?? 1
        payloadHash = try c.decode(String.self, forKey: .payloadHash)
        lastMigrationAction = try c.decodeIfPresent(AutoSmallTaskMigrationAction.self, forKey: .lastMigrationAction)
            ?? .inserted
        lastMigrationReason = try c.decodeIfPresent(String.self, forKey: .lastMigrationReason)
            ?? "legacy_payload_version"
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userID, forKey: .userID)
        try c.encode(businessKey, forKey: .businessKey)
        try c.encode(smallTaskCode, forKey: .smallTaskCode)
        try c.encode(localSmallTaskID, forKey: .localSmallTaskID)
        try c.encode(definitionVersion, forKey: .definitionVersion)
        try c.encode(minimumRuntimeVersion, forKey: .minimumRuntimeVersion)
        try c.encode(toolContractVersion, forKey: .toolContractVersion)
        try c.encode(payloadHash, forKey: .payloadHash)
        try c.encode(lastMigrationAction, forKey: .lastMigrationAction)
        try c.encode(lastMigrationReason, forKey: .lastMigrationReason)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
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
