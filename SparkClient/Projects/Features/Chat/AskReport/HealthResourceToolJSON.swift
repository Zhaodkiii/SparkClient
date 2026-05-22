import Foundation

// MARK: - list_member_health_sources

struct ListMemberHealthSourcesResponse: Codable, Equatable, Sendable {
    let version: Int
    let memberId: Int
    let query: ListMemberHealthSourcesQuery
    let candidates: [HealthResourceToolCandidateDTO]
    let truncated: Bool
}

struct ListMemberHealthSourcesQuery: Codable, Equatable, Sendable {
    let keyword: String?
    /// 类型筛选；`nil` 表示未按类型过滤。与 `resource_type` 单值参数二选一或合并后写入。
    let resourceTypes: [String]?
    let startDate: String?
    let endDate: String?
    let limit: Int
}

struct HealthResourceToolCandidateDTO: Codable, Equatable, Sendable, Identifiable {
    let resourceType: String
    let resourceId: Int
    let memberId: Int
    let title: String
    let occurredAt: String?
    let institution: String?
    let matchedFields: [String]
    let matchReason: String
    let confidence: Double

    var id: String { identity.cacheKey }

    var identity: HealthResourceIdentity {
        HealthResourceIdentity(resourceType: resourceType, resourceID: resourceId, memberID: memberId)
    }
}

extension HealthResourceIdentity {
    init(_ candidate: HealthResourceToolCandidateDTO) {
        self.init(resourceType: candidate.resourceType, resourceID: candidate.resourceId, memberID: candidate.memberId)
    }

    init?(_ dto: HealthResourceToolReferenceDTO) {
        guard let memberId = dto.memberId else { return nil }
        self.init(resourceType: dto.resourceType, resourceID: dto.resourceId, memberID: memberId)
    }
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
    let resourceId: Int
    /// 工具输出必填；`references` 批量入参可省略，由 scope 补齐。
    let memberId: Int?
}

// MARK: - get_health_resource_context

struct GetHealthResourceContextResponse: Codable, Equatable, Sendable {
    let version: Int
    let reference: HealthResourceToolReferenceDTO
    let contextText: String
    let topic: String?
}

/// 批量解读上下文（version=2）：一次工具调用返回多份资料。
struct GetHealthResourcesContextResponse: Codable, Equatable, Sendable {
    let version: Int
    let memberId: Int
    let topic: String?
    let contexts: [HealthResourceContextItemDTO]
    let combinedContextText: String
}

struct HealthResourceContextItemDTO: Codable, Equatable, Sendable {
    let refIndex: Int
    let reference: HealthResourceToolReferenceDTO
    let contextText: String
    let resolveStatus: String
}

enum HealthResourceContextReferenceParser {
    private static let maxBatchCount = HealthResourceSendValidator.maxRefs
    private static let decoder = JSONDecoder.default

    /// 解析 `references` JSON 或单条 `resource_type` + `resource_id`。
    static func identities(
        from arguments: [String: String],
        scopeMemberID: Int
    ) -> [HealthResourceIdentity]? {
        if let batch = parseReferencesJSON(arguments["references"], scopeMemberID: scopeMemberID) {
            return batch
        }
        guard let resourceType = arguments["resource_type"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              resourceType.isEmpty == false,
              HealthResourceType(rawValue: resourceType) != nil,
              let resourceID = Int(arguments["resource_id"] ?? ""),
              resourceID > 0 else {
            return nil
        }
        let memberID = Int(arguments["member_id"] ?? "") ?? scopeMemberID
        guard memberID == scopeMemberID else { return nil }
        return [HealthResourceIdentity(resourceType: resourceType, resourceID: resourceID, memberID: memberID)]
    }

    static func parseReferencesJSON(
        _ raw: String?,
        scopeMemberID: Int
    ) -> [HealthResourceIdentity]? {
        guard let inputs = decodeReferences(raw), inputs.isEmpty == false else {
            return nil
        }
        guard inputs.count <= maxBatchCount else { return nil }
        let resolvedScope = resolveScopeMemberID(inputs: inputs, scopeMemberID: scopeMemberID)
        guard let resolvedScope else { return nil }
        var identities: [HealthResourceIdentity] = []
        for input in inputs {
            guard HealthResourceType(rawValue: input.resourceType) != nil,
                  input.resourceId > 0 else { return nil }
            let memberID = input.memberId ?? resolvedScope
            guard memberID == resolvedScope else { return nil }
            identities.append(
                HealthResourceIdentity(
                    resourceType: input.resourceType,
                    resourceID: input.resourceId,
                    memberID: memberID
                )
            )
        }
        return identities
    }

    /// 从 `references` 推断成员 ID（仅传 references、未传 member_id 时用于 scope 解析）。
    static func scopeMemberID(fromReferencesJSON raw: String?) -> Int? {
        guard let inputs = decodeReferences(raw), inputs.isEmpty == false else {
            return nil
        }
        return resolveScopeMemberID(inputs: inputs, scopeMemberID: nil)
    }

    private static func decodeReferences(_ raw: String?) -> [HealthResourceToolReferenceDTO]? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }
        return try? decoder.decode([HealthResourceToolReferenceDTO].self, fromJSONString: raw)
    }

    private static func resolveScopeMemberID(
        inputs: [HealthResourceToolReferenceDTO],
        scopeMemberID: Int?
    ) -> Int? {
        let explicitMembers = inputs.compactMap(\.memberId)
        if let scopeMemberID, scopeMemberID > 0 {
            if explicitMembers.isEmpty { return scopeMemberID }
            guard explicitMembers.allSatisfy({ $0 == scopeMemberID }) else { return nil }
            return scopeMemberID
        }
        guard let first = explicitMembers.first, explicitMembers.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }

    /// 从 `list_member_health_sources` 的 candidates 构造批量引用。
    static func identities(from candidates: [HealthResourceToolCandidateDTO], scopeMemberID: Int) -> [HealthResourceIdentity] {
        Array(
            candidates
                .prefix(maxBatchCount)
                .map { HealthResourceIdentity($0) }
                .filter { $0.memberID == scopeMemberID }
        )
    }
}
