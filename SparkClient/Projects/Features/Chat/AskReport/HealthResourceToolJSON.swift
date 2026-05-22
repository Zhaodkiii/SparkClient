import Foundation

// MARK: - list_member_health_sources

struct ListMemberHealthSourcesResponse: Codable, Equatable, Sendable {
    let version: Int
    let memberID: Int
    let query: ListMemberHealthSourcesQuery
    let candidates: [HealthResourceToolCandidateDTO]
    let truncated: Bool
}

struct ListMemberHealthSourcesQuery: Codable, Equatable, Sendable {
    let keyword: String?
    let resourceType: String?
    let startDate: String?
    let endDate: String?
    let limit: Int
}

struct HealthResourceToolCandidateDTO: Codable, Equatable, Sendable, Identifiable {
    let resourceType: String
    let resourceID: Int
    let memberID: Int
    let title: String
    let occurredAt: String?
    let institution: String?
    let matchedFields: [String]
    let matchReason: String
    let confidence: Double

    var id: String { "\(resourceType):\(resourceID):\(memberID)" }
}

struct HealthResourceToolErrorResponse: Codable, Equatable, Sendable {
    let version: Int
    let error: String
    let message: String
}

// MARK: - get_health_resource_reference

struct GetHealthResourceReferenceResponse: Codable, Equatable, Sendable {
    let version: Int
    let reference: HealthResourceToolReferenceDTO?
    let resolveStatus: String
    let displayTitle: String?
    let displaySubtitle: String?
}

struct HealthResourceToolReferenceDTO: Codable, Equatable, Sendable {
    let resourceType: String
    let resourceID: Int
    let memberID: Int
}

// MARK: - get_health_resource_context

struct GetHealthResourceContextResponse: Codable, Equatable, Sendable {
    let version: Int
    let reference: HealthResourceToolReferenceDTO
    let contextText: String
    let topic: String?
}
