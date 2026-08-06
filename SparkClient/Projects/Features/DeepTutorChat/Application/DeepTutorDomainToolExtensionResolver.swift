import Foundation

/// 单个工具的挂载/抑制决策及原因，供排障与 snapshot 使用。
nonisolated struct DeepTutorToolGateResult: Equatable, Sendable, Codable {
    var toolName: String
    var allowed: Bool
    var reason: String
}

/// 一个领域（健康数据 / 健康报告 / 天气定位）的扩展工具解析结果。
/// Spark 项目扩展层：这些工具不属于 DeepTutor-main canonical 工具集，
/// 必须显式标注 `source`，不能伪装成 canonical 工具。
nonisolated struct DeepTutorDomainToolExtensionResult: Equatable, Sendable {
    var source: String
    var sparkToolNames: Set<String>
    var gateResults: [DeepTutorToolGateResult]
    var eligible: Bool
    var ineligibleReason: String?
    var subdomain: String?
    var nextPhase: String?
}

/// 负责把结构化健康/报告/天气意图转换为 Spark 工具面（含成员选择前置 gate）。
///
/// 与 `DeepTutorToolCompositionPolicy`（对齐 DeepTutor-main canonical 工具组合）
/// 是并行、独立的两层：这一层只处理 SparkClient 自有的健康/成员/报告/天气工具，
/// 最终结果在 `DeepTutorToolPolicyResolver` 中合并进同一个 policy result。
enum DeepTutorDomainToolExtensionResolver: Sendable {
    nonisolated static func resolve(
        context: DeepTutorToolMountContext,
        structuredIntents: [DeepTutorStructuredToolIntent]
    ) -> [DeepTutorDomainToolExtensionResult] {
        [
            resolveHealthData(context: context, structuredIntents: structuredIntents),
            resolveHealthReport(context: context, structuredIntents: structuredIntents),
            resolveWeather(context: context, structuredIntents: structuredIntents),
        ]
    }

    // MARK: - Health data

    private nonisolated static func resolveHealthData(
        context: DeepTutorToolMountContext,
        structuredIntents: [DeepTutorStructuredToolIntent]
    ) -> DeepTutorDomainToolExtensionResult {
        let healthIntent = structuredIntents.first { $0.domain == .healthData }
        let forced = context.forcedDomainIntents.contains("health_data")
        guard healthIntent != nil || forced else {
            return ineligible(source: "health_data", reason: "intent_not_matched")
        }
        guard context.healthDataCapabilityAvailable else {
            return ineligible(source: "health_data", reason: "health_capability_unavailable")
        }

        let subdomain = healthIntent?.subdomain ?? .general
        let fetchTools = fetchTools(for: subdomain)

        var tools = Set<String>()
        var gates: [DeepTutorToolGateResult] = []
        let nextPhase: String

        if context.hasSelectedMember {
            nextPhase = "health_fetch"
            tools.insert(SparkToolName.getCurrentMember.rawValue)
            tools.insert(SparkToolName.queryMemberProfile.rawValue)
            tools.formUnion(fetchTools)
            for toolName in [SparkToolName.getCurrentMember.rawValue, SparkToolName.queryMemberProfile.rawValue] + fetchTools.sorted() {
                gates.append(
                    DeepTutorToolGateResult(
                        toolName: toolName,
                        allowed: true,
                        reason: "member_selected+\(subdomain.rawValue)"
                    )
                )
            }
            gates.append(
                DeepTutorToolGateResult(
                    toolName: SparkToolName.requestMemberSelection.rawValue,
                    allowed: false,
                    reason: "member_already_selected"
                )
            )
            for toolName in allFetchTools.subtracting(fetchTools) {
                gates.append(
                    DeepTutorToolGateResult(
                        toolName: toolName,
                        allowed: false,
                        reason: "subdomain_not_matched:\(subdomain.rawValue)"
                    )
                )
            }
        } else {
            nextPhase = "member_selection"
            tools.insert(SparkToolName.requestMemberSelection.rawValue)
            tools.insert(SparkToolName.getCurrentMember.rawValue)
            tools.insert(SparkToolName.findMember.rawValue)
            for toolName in [
                SparkToolName.requestMemberSelection.rawValue,
                SparkToolName.getCurrentMember.rawValue,
                SparkToolName.findMember.rawValue,
            ] {
                gates.append(
                    DeepTutorToolGateResult(
                        toolName: toolName,
                        allowed: true,
                        reason: "member_not_selected_gate+\(subdomain.rawValue)"
                    )
                )
            }
            for toolName in allFetchTools {
                gates.append(
                    DeepTutorToolGateResult(
                        toolName: toolName,
                        allowed: false,
                        reason: "member_required"
                    )
                )
            }
        }

        return DeepTutorDomainToolExtensionResult(
            source: "health_data",
            sparkToolNames: tools,
            gateResults: gates,
            eligible: true,
            ineligibleReason: nil,
            subdomain: subdomain.rawValue,
            nextPhase: nextPhase
        )
    }

    // MARK: - Health report

    private nonisolated static func resolveHealthReport(
        context: DeepTutorToolMountContext,
        structuredIntents: [DeepTutorStructuredToolIntent]
    ) -> DeepTutorDomainToolExtensionResult {
        let intentMatched = structuredIntents.contains { $0.domain == .healthReport }
            || context.forcedDomainIntents.contains("health_report")
            || context.hasHealthResourceContext
        guard intentMatched else {
            return ineligible(source: "health_report", reason: "intent_not_matched")
        }

        var tools: Set<String> = [
            SparkToolName.listMemberHealthSources.rawValue,
            SparkToolName.getHealthResourceReference.rawValue,
        ]
        var gates: [DeepTutorToolGateResult] = [
            SparkToolName.listMemberHealthSources.rawValue,
            SparkToolName.getHealthResourceReference.rawValue,
        ].map { DeepTutorToolGateResult(toolName: $0, allowed: true, reason: "health_report_intent") }

        if context.hasHealthResourceContext {
            tools.insert(SparkToolName.getHealthResourceContext.rawValue)
            gates.append(
                DeepTutorToolGateResult(
                    toolName: SparkToolName.getHealthResourceContext.rawValue,
                    allowed: true,
                    reason: "has_health_resource_context"
                )
            )
        } else {
            gates.append(
                DeepTutorToolGateResult(
                    toolName: SparkToolName.getHealthResourceContext.rawValue,
                    allowed: false,
                    reason: "no_health_resource_context"
                )
            )
        }

        let nextPhase: String
        if context.hasSelectedMember == false {
            nextPhase = "member_selection"
            tools.formUnion([
                SparkToolName.requestMemberSelection.rawValue,
                SparkToolName.getCurrentMember.rawValue,
            ])
            gates.append(
                DeepTutorToolGateResult(
                    toolName: SparkToolName.requestMemberSelection.rawValue,
                    allowed: true,
                    reason: "member_not_selected_gate"
                )
            )
            gates.append(
                DeepTutorToolGateResult(
                    toolName: SparkToolName.getCurrentMember.rawValue,
                    allowed: true,
                    reason: "member_not_selected_gate"
                )
            )
        } else {
            nextPhase = "health_report_fetch"
        }

        return DeepTutorDomainToolExtensionResult(
            source: "health_report",
            sparkToolNames: tools,
            gateResults: gates,
            eligible: true,
            ineligibleReason: nil,
            subdomain: nil,
            nextPhase: nextPhase
        )
    }

    // MARK: - Weather / location

    private nonisolated static func resolveWeather(
        context: DeepTutorToolMountContext,
        structuredIntents: [DeepTutorStructuredToolIntent]
    ) -> DeepTutorDomainToolExtensionResult {
        let intentMatched = structuredIntents.contains { $0.domain == .weatherLocation }
            || context.forcedDomainIntents.contains("weather_location")
        guard intentMatched else {
            return ineligible(source: "weather_location", reason: "intent_not_matched")
        }
        guard context.weatherToolEnabled else {
            return ineligible(source: "weather_location", reason: "weather_disabled")
        }

        var tools: Set<String> = [
            SparkToolName.queryWeather.rawValue,
            SparkToolName.queryLocation.rawValue,
        ]
        var gates: [DeepTutorToolGateResult] = [
            DeepTutorToolGateResult(toolName: SparkToolName.queryWeather.rawValue, allowed: true, reason: "weather_intent"),
            DeepTutorToolGateResult(toolName: SparkToolName.queryLocation.rawValue, allowed: true, reason: "weather_intent"),
        ]

        let hasExplicitCity = DeepTutorWeatherLocationHint.hasExplicitCity(in: context.userInput)
        let nextPhase: String

        if context.hasLocationPermission {
            tools.insert(SparkToolName.getCurrentLocation.rawValue)
            gates.append(
                DeepTutorToolGateResult(
                    toolName: SparkToolName.getCurrentLocation.rawValue,
                    allowed: true,
                    reason: "has_location_permission"
                )
            )
            nextPhase = "weather_fetch"
        } else {
            gates.append(
                DeepTutorToolGateResult(
                    toolName: SparkToolName.getCurrentLocation.rawValue,
                    allowed: false,
                    reason: "no_location_permission"
                )
            )
            if hasExplicitCity {
                nextPhase = "weather_fetch"
            } else {
                tools.insert(SparkToolName.askUserQuestion.rawValue)
                gates.append(
                    DeepTutorToolGateResult(
                        toolName: SparkToolName.askUserQuestion.rawValue,
                        allowed: true,
                        reason: "city_required"
                    )
                )
                nextPhase = "weather_city_prompt"
            }
        }

        return DeepTutorDomainToolExtensionResult(
            source: "weather_location",
            sparkToolNames: tools,
            gateResults: gates,
            eligible: true,
            ineligibleReason: nil,
            subdomain: nil,
            nextPhase: nextPhase
        )
    }

    // MARK: - Tool sets

    private nonisolated static let allFetchTools: Set<String> = [
        SparkToolName.fetchStepDetails.rawValue,
        SparkToolName.fetchEnergyDetails.rawValue,
        SparkToolName.fetchNutritionDetails.rawValue,
        SparkToolName.fetchSleepDetails.rawValue,
        SparkToolName.fetchWorkoutDetails.rawValue,
        SparkToolName.makeNutritionData.rawValue,
    ]

    private nonisolated static func fetchTools(for subdomain: DeepTutorHealthDataSubdomain) -> Set<String> {
        switch subdomain {
        case .sleep:
            return [SparkToolName.fetchSleepDetails.rawValue]
        case .steps:
            return [SparkToolName.fetchStepDetails.rawValue]
        case .energy:
            return [SparkToolName.fetchEnergyDetails.rawValue]
        case .nutrition:
            return [
                SparkToolName.fetchNutritionDetails.rawValue,
                SparkToolName.makeNutritionData.rawValue,
            ]
        case .workout:
            return [SparkToolName.fetchWorkoutDetails.rawValue]
        case .general:
            return allFetchTools
        }
    }

    private nonisolated static func ineligible(
        source: String,
        reason: String
    ) -> DeepTutorDomainToolExtensionResult {
        DeepTutorDomainToolExtensionResult(
            source: source,
            sparkToolNames: [],
            gateResults: [],
            eligible: false,
            ineligibleReason: reason,
            subdomain: nil,
            nextPhase: nil
        )
    }
}
