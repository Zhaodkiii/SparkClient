import Foundation

struct HealthResourceListQuery: Sendable, Equatable {
    /// `nil` 或空表示不按类型过滤；非空时仅保留列出的 `HealthResourceType.rawValue`。
    let resourceTypes: [String]?
    let keyword: String?
    let startDate: String?
    let endDate: String?
    let limit: Int
}

struct HealthResourceAIContext: Sendable, Equatable {
    let identity: HealthResourceIdentity
    let contextText: String
    let topic: String?
}

/// ToolHub 依赖的健康资料能力边界（实现位于 Chat Feature）。
protocol HealthResourceToolService: Sendable {
    func listSources(
        query: HealthResourceListQuery,
        memberID: Int
    ) async -> Result<(candidates: [HealthResourceToolCandidateDTO], truncated: Bool), HealthResourceLoadError>

    func validateReference(
        _ identity: HealthResourceIdentity
    ) async -> Result<HealthResourceCardSummary, HealthResourceLoadError>

    func resolveContext(
        _ identity: HealthResourceIdentity,
        topic: String?
    ) async -> Result<HealthResourceAIContext, HealthResourceLoadError>

    /// 一次解析多份资料解读上下文（顺序与 `ref_index` 一致）。
    func resolveContexts(
        _ identities: [HealthResourceIdentity],
        memberID: Int,
        topic: String?
    ) async -> Result<GetHealthResourcesContextResponse, HealthResourceLoadError>
}
