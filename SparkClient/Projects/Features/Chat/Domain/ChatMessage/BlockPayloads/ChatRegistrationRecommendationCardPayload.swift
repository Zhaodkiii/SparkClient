import Foundation

nonisolated struct ChatRegistrationRecommendationCardPayload: Codable, Equatable, Sendable, Identifiable {
    let schemaVersion: Int
    let hospitalID: UUID
    let hospitalName: String
    let departmentID: UUID
    let departmentName: String
    let agentID: UUID?
    let doctorID: UUID?
    let doctorName: String?
    let doctorTitle: String?
    let doctorAvatarURL: String?
    let reasonSummary: String

    // `JSONDecoder.convertFromSnakeCase` maps `hospital_id` to `hospitalId`,
    // while this model intentionally uses the project-wide `ID` acronym.
    // Explicit wire keys keep `hospitalID`/`departmentID`/`doctorID` stable
    // across Core Data payloads, chat sync, and older persisted cards.
    private enum WireCodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case hospitalID = "hospital_id"
        case hospitalName = "hospital_name"
        case departmentID = "department_id"
        case departmentName = "department_name"
        case agentID = "agent_id"
        case doctorID = "doctor_id"
        case doctorName = "doctor_name"
        case doctorTitle = "doctor_title"
        case doctorAvatarURL = "doctor_avatar_url"
        case reasonSummary = "reason_summary"
    }

    // Keys after JSONDecoder.convertFromSnakeCase normalization. Foundation
    // normalizes `hospital_id` to `hospitalId` (not `hospitalID`).
    private enum NormalizedCodingKeys: String, CodingKey {
        case schemaVersion
        case hospitalId
        case hospitalName
        case departmentId
        case departmentName
        case agentId
        case doctorId
        case doctorName
        case doctorTitle
        case doctorAvatarUrl
        case reasonSummary
    }

    // Payloads written by the first implementation used these camelCase keys.
    private enum LegacyCamelCodingKeys: String, CodingKey {
        case schemaVersion
        case hospitalID
        case hospitalName
        case departmentID
        case departmentName
        case agentID
        case doctorID
        case doctorName
        case doctorTitle
        case doctorAvatarURL
        case reasonSummary
    }

    var id: String {
        "\(hospitalID.uuidString):\(departmentID.uuidString):\(agentID?.uuidString ?? "department")"
    }

    var isDoctorSpecific: Bool { agentID != nil && doctorID != nil }

    init(
        schemaVersion: Int = 1,
        hospitalID: UUID,
        hospitalName: String,
        departmentID: UUID,
        departmentName: String,
        agentID: UUID? = nil,
        doctorID: UUID? = nil,
        doctorName: String? = nil,
        doctorTitle: String? = nil,
        doctorAvatarURL: String? = nil,
        reasonSummary: String
    ) {
        self.schemaVersion = schemaVersion
        self.hospitalID = hospitalID
        self.hospitalName = hospitalName
        self.departmentID = departmentID
        self.departmentName = departmentName
        self.agentID = agentID
        self.doctorID = doctorID
        self.doctorName = doctorName
        self.doctorTitle = doctorTitle
        self.doctorAvatarURL = doctorAvatarURL
        self.reasonSummary = String(reasonSummary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    }

    init(from decoder: Decoder) throws {
        let normalized = try decoder.container(keyedBy: NormalizedCodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCamelCodingKeys.self)

        func required<T: Decodable>(
            _ type: T.Type,
            normalizedKey: NormalizedCodingKeys,
            legacyKey: LegacyCamelCodingKeys
        ) throws -> T {
            if let value = try normalized.decodeIfPresent(type, forKey: normalizedKey) {
                return value
            }
            return try legacy.decode(type, forKey: legacyKey)
        }

        func optional<T: Decodable>(
            _ type: T.Type,
            normalizedKey: NormalizedCodingKeys,
            legacyKey: LegacyCamelCodingKeys
        ) throws -> T? {
            if let value = try normalized.decodeIfPresent(type, forKey: normalizedKey) {
                return value
            }
            return try legacy.decodeIfPresent(type, forKey: legacyKey)
        }

        self.init(
            schemaVersion: try normalized.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? legacy.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? 1,
            hospitalID: try required(UUID.self, normalizedKey: .hospitalId, legacyKey: .hospitalID),
            hospitalName: try required(String.self, normalizedKey: .hospitalName, legacyKey: .hospitalName),
            departmentID: try required(UUID.self, normalizedKey: .departmentId, legacyKey: .departmentID),
            departmentName: try required(String.self, normalizedKey: .departmentName, legacyKey: .departmentName),
            agentID: try optional(UUID.self, normalizedKey: .agentId, legacyKey: .agentID),
            doctorID: try optional(UUID.self, normalizedKey: .doctorId, legacyKey: .doctorID),
            doctorName: try optional(String.self, normalizedKey: .doctorName, legacyKey: .doctorName),
            doctorTitle: try optional(String.self, normalizedKey: .doctorTitle, legacyKey: .doctorTitle),
            doctorAvatarURL: try optional(String.self, normalizedKey: .doctorAvatarUrl, legacyKey: .doctorAvatarURL),
            reasonSummary: try required(String.self, normalizedKey: .reasonSummary, legacyKey: .reasonSummary)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireCodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(hospitalID, forKey: .hospitalID)
        try container.encode(hospitalName, forKey: .hospitalName)
        try container.encode(departmentID, forKey: .departmentID)
        try container.encode(departmentName, forKey: .departmentName)
        try container.encodeIfPresent(agentID, forKey: .agentID)
        try container.encodeIfPresent(doctorID, forKey: .doctorID)
        try container.encodeIfPresent(doctorName, forKey: .doctorName)
        try container.encodeIfPresent(doctorTitle, forKey: .doctorTitle)
        try container.encodeIfPresent(doctorAvatarURL, forKey: .doctorAvatarURL)
        try container.encode(reasonSummary, forKey: .reasonSummary)
    }
}
