import Foundation

struct SparkMedicalMemberAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    struct RemoteMember: Decodable, Sendable, Equatable {
        let id: Int
        let name: String
        let gender: String
        let relationship: String
        let birthDate: Date?
        let bloodType: String
        let allergies: [String]
        let chronicConditions: [String]
        let notes: String
        let avatarUrl: String
        let isPrimary: Bool
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case gender
            case relationship
            case birthDate = "birth_date"
            case bloodType = "blood_type"
            case allergies
            case chronicConditions = "chronic_conditions"
            case notes
            case avatarUrl = "avatar_url"
            case isPrimary = "is_primary"
            case updatedAt = "updated_at"
        }
    }

    struct UpsertMemberPayload: Encodable, Sendable {
        let name: String
        let relationship: String
        let gender: String
        let birthDate: Date?
        let bloodType: String
        let allergies: [String]
        let chronicConditions: [String]
        let notes: String
        let avatarUrl: String
        let isPrimary: Bool

        enum CodingKeys: String, CodingKey {
            case name
            case relationship
            case gender
            case birthDate = "birth_date"
            case bloodType = "blood_type"
            case allergies
            case chronicConditions = "chronic_conditions"
            case notes
            case avatarUrl = "avatar_url"
            case isPrimary = "is_primary"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(relationship, forKey: .relationship)
            try container.encode(gender, forKey: .gender)
            if let birthDate {
                try container.encode(MedicalDateCoding.encodeDateOnly(birthDate), forKey: .birthDate)
            } else {
                try container.encodeNil(forKey: .birthDate)
            }
            try container.encode(bloodType, forKey: .bloodType)
            try container.encode(allergies, forKey: .allergies)
            try container.encode(chronicConditions, forKey: .chronicConditions)
            try container.encode(notes, forKey: .notes)
            try container.encode(avatarUrl, forKey: .avatarUrl)
            try container.encode(isPrimary, forKey: .isPrimary)
        }
    }

    func listMembers() async throws -> [RemoteMember] {
        let operation = CacheableSparkNetworkOperation(
            name: "Medical.Member.List",
            apiName: "MedicalMemberAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/medical/members/",
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: true,
                    serialKey: "medical.members.list",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal,
                    etagTTL: 120
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData([RemoteMember].self, from: response, decoder: .medicalMemberISO8601)
    }

    func createMember(_ payload: UpsertMemberPayload) async throws -> RemoteMember {
        let operation = CacheableSparkNetworkOperation(
            name: "Medical.Member.Create",
            apiName: "MedicalMemberAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/medical/members/",
                body: .json(AnyEncodable(payload)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "medical.members.create",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(RemoteMember.self, from: response, decoder: .medicalMemberISO8601)
    }

    func updateMember(remoteID: Int, payload: UpsertMemberPayload) async throws -> RemoteMember {
        let operation = CacheableSparkNetworkOperation(
            name: "Medical.Member.Update",
            apiName: "MedicalMemberAPI",
            request: SparkNetworkRequest(
                method: .put,
                path: "/api/v1/medical/members/\(remoteID)/",
                body: .json(AnyEncodable(payload)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "medical.members.update.\(remoteID)",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(RemoteMember.self, from: response, decoder: .medicalMemberISO8601)
    }

    func deleteMember(remoteID: Int) async throws {
        let operation = CacheableSparkNetworkOperation(
            name: "Medical.Member.Delete",
            apiName: "MedicalMemberAPI",
            request: SparkNetworkRequest(
                method: .delete,
                path: "/api/v1/medical/members/\(remoteID)/",
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "medical.members.delete.\(remoteID)",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        _ = try APIResponseDecoder.decodeWrappedData(JSONValue?.self, from: response, decoder: .medicalMemberISO8601)
    }
}

private extension JSONDecoder {
    static let medicalMemberISO8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(MedicalDateCoding.decodeFlexibleDate(from:))
        return decoder
    }()
}
