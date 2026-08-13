import Foundation

nonisolated enum ToolModelEgressConsentCategory: String, Codable, Sendable, CaseIterable {
    case location
    case weather
    case health

    var localizationKey: String {
        switch self {
        case .location:
            return "ai_settings.tool_consent.category.location"
        case .weather:
            return "ai_settings.tool_consent.category.weather"
        case .health:
            return "ai_settings.tool_consent.category.health"
        }
    }

    var displayTitle: String {
        switch self {
        case .location:
            return L10n.text(localizationKey, fallback: "位置")
        case .weather:
            return L10n.text(localizationKey, fallback: "天气")
        case .health:
            return L10n.text(localizationKey, fallback: "健康")
        }
    }
}

nonisolated struct ToolModelEgressConsentDescriptor: Equatable, Sendable {
    let toolName: String
    let category: ToolModelEgressConsentCategory
    let localizationKeyPrefix: String
    let relatedToolNames: [String]
    let dataLineCount: Int
    let dataSourceLineCount: Int

    var displayName: String {
        SparkToolName.displayName(for: toolName)
    }

    var normalizedToolName: String {
        ToolModelEgressConsentPreferences.normalizeToolName(toolName)
    }

    var categoryTitle: String {
        category.displayTitle
    }

    var summary: String {
        L10n.text(
            "\(localizationKeyPrefix).summary",
            fallback: "Tool result may be sent to the model for personalized responses."
        )
    }

    var dataLines: [String] {
        L10n.numberedTexts(prefix: "\(localizationKeyPrefix).data", count: dataLineCount)
    }

    var whyItNeedsAI: String {
        L10n.text(
            "\(localizationKeyPrefix).why",
            fallback: "The model needs this tool result to continue generating a relevant response."
        )
    }

    var denyImpact: String {
        L10n.text(
            "\(localizationKeyPrefix).deny_impact",
            fallback: "If denied, the model will not receive the original tool result."
        )
    }

    var dataSourceLines: [String] {
        L10n.numberedTexts(prefix: "\(localizationKeyPrefix).source", count: dataSourceLineCount)
    }
}

nonisolated enum ToolModelEgressConsentResolution: Equatable, Sendable {
    case allowWithoutPrompt
    case askEveryTime
    case deny(reason: String)
}

struct ToolModelEgressConsentPolicy: Sendable {
    private var defaultDenyReason: String {
        L10n.text(
            "ai_settings.tool_consent.runtime.always_deny_reason",
            fallback: "用户已将该工具配置为永久拒绝发送到 AI。"
        )
    }

    func evaluate(
        result: ToolExecutionResult,
        providerCompany: String?,
        snapshot: AISettingsSnapshot
    ) -> ToolModelEgressConsentResolution {
        guard result.sensitive else { return .allowWithoutPrompt }
        guard Self.managedToolNames.contains(Self.normalize(result.toolName)) else { return .allowWithoutPrompt }
        guard (providerCompany ?? "").uppercased() != "LOCAL" else { return .allowWithoutPrompt }
        guard Self.resultContainsShareableUserData(result) else { return .allowWithoutPrompt }

        switch snapshot.toolModelEgressConsentPreferences.mode(for: result.toolName) {
        case .alwaysAllow:
            return .allowWithoutPrompt
        case .askEveryTime:
            return .askEveryTime
        case .alwaysDeny:
            return .deny(reason: defaultDenyReason)
        }
    }

    func descriptor(for toolName: String) -> ToolModelEgressConsentDescriptor? {
        Self.descriptor(for: toolName)
    }

    func controls(toolName: String) -> Bool {
        Self.managedToolNames.contains(Self.normalize(toolName))
    }

    static func descriptor(for toolName: String) -> ToolModelEgressConsentDescriptor? {
        descriptors[normalize(toolName)]
    }

    static func managedDescriptors() -> [ToolModelEgressConsentDescriptor] {
        descriptors.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func modeSummary(
        snapshot: AISettingsSnapshot,
        descriptor: ToolModelEgressConsentDescriptor
    ) -> ToolModelEgressConsentMode {
        snapshot.toolModelEgressConsentPreferences.mode(for: descriptor.toolName)
    }

    static let managedToolNames: Set<String> = Set(descriptors.keys)

    private static func resultContainsShareableUserData(_ result: ToolExecutionResult) -> Bool {
        guard let descriptor = descriptor(for: result.toolName) else { return true }
        switch descriptor.category {
        case .health:
            return healthOutputIndicatesNoUserData(result.outputText) == false
        case .location, .weather:
            return true
        }
    }

    private static func healthOutputIndicatesNoUserData(_ output: String) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }

        let noDataPrefixes = [
            L10n.text("health.tool.error.no_matching_health"),
            L10n.text("health.tool.error.no_workouts", fallback: "No matching workout records found."),
            L10n.text("health.tool.error.no_nutrition", fallback: "No nutrition data found."),
            L10n.text("health.tool.error.no_sleep", fallback: "No sleep data found."),
            L10n.text("health.tool.error.no_sleep_range", fallback: "No sleep data found in the requested date range.")
        ]

        if noDataPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }

        let sleepEmptyLine = L10n.text("chat.sleep.readable.empty", fallback: "  - No sleep data")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains(sleepEmptyLine)
    }

    private static let descriptors: [String: ToolModelEgressConsentDescriptor] = {
        let values: [ToolModelEgressConsentDescriptor] = [
            ToolModelEgressConsentDescriptor(
                toolName: SparkToolName.getCurrentLocation.rawValue,
                category: .location,
                localizationKeyPrefix: "ai_settings.tool_consent.descriptor.get_current_location",
                relatedToolNames: [
                    SparkToolName.getCurrentLocation.rawValue,
                    SparkToolName.queryLocation.rawValue,
                    SparkToolName.queryWeather.rawValue
                ],
                dataLineCount: 3,
                dataSourceLineCount: 2
            ),
            ToolModelEgressConsentDescriptor(
                toolName: SparkToolName.queryLocation.rawValue,
                category: .location,
                localizationKeyPrefix: "ai_settings.tool_consent.descriptor.query_location",
                relatedToolNames: [
                    SparkToolName.queryLocation.rawValue,
                    SparkToolName.getCurrentLocation.rawValue,
                    SparkToolName.queryWeather.rawValue
                ],
                dataLineCount: 3,
                dataSourceLineCount: 1
            ),
            ToolModelEgressConsentDescriptor(
                toolName: SparkToolName.queryWeather.rawValue,
                category: .weather,
                localizationKeyPrefix: "ai_settings.tool_consent.descriptor.query_weather",
                relatedToolNames: [
                    SparkToolName.queryWeather.rawValue,
                    SparkToolName.queryLocation.rawValue,
                    SparkToolName.getCurrentLocation.rawValue
                ],
                dataLineCount: 3,
                dataSourceLineCount: 2
            ),
            ToolModelEgressConsentDescriptor(
                toolName: SparkToolName.fetchStepDetails.rawValue,
                category: .health,
                localizationKeyPrefix: "ai_settings.tool_consent.descriptor.fetch_step_details",
                relatedToolNames: [SparkToolName.fetchStepDetails.rawValue],
                dataLineCount: 3,
                dataSourceLineCount: 1
            ),
            ToolModelEgressConsentDescriptor(
                toolName: SparkToolName.fetchEnergyDetails.rawValue,
                category: .health,
                localizationKeyPrefix: "ai_settings.tool_consent.descriptor.fetch_energy_details",
                relatedToolNames: [SparkToolName.fetchEnergyDetails.rawValue],
                dataLineCount: 3,
                dataSourceLineCount: 1
            ),
            ToolModelEgressConsentDescriptor(
                toolName: SparkToolName.fetchNutritionDetails.rawValue,
                category: .health,
                localizationKeyPrefix: "ai_settings.tool_consent.descriptor.fetch_nutrition_details",
                relatedToolNames: [SparkToolName.fetchNutritionDetails.rawValue],
                dataLineCount: 3,
                dataSourceLineCount: 1
            ),
            ToolModelEgressConsentDescriptor(
                toolName: SparkToolName.fetchSleepDetails.rawValue,
                category: .health,
                localizationKeyPrefix: "ai_settings.tool_consent.descriptor.fetch_sleep_details",
                relatedToolNames: [SparkToolName.fetchSleepDetails.rawValue],
                dataLineCount: 3,
                dataSourceLineCount: 1
            ),
            ToolModelEgressConsentDescriptor(
                toolName: SparkToolName.fetchWorkoutDetails.rawValue,
                category: .health,
                localizationKeyPrefix: "ai_settings.tool_consent.descriptor.fetch_workout_details",
                relatedToolNames: [SparkToolName.fetchWorkoutDetails.rawValue],
                dataLineCount: 3,
                dataSourceLineCount: 1
            ),
        ]
        return Dictionary(uniqueKeysWithValues: values.map { ($0.normalizedToolName, $0) })
    }()

    private static func normalize(_ value: String) -> String {
        ToolModelEgressConsentPreferences.normalizeToolName(value)
    }
}
