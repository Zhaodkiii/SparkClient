import Foundation

/// 出站前校验：system prompt 提到的工具，必须真的出现在本轮 schema 里，
/// 否则模型只能在 reasoning 中承认「没有相关工具」而无法真正调用。
enum DeepTutorPromptSchemaConsistencyChecker: Sendable {
    private nonisolated static let watchedTools: [(toolName: String, promptMarker: String)] = [
        (SparkToolName.requestMemberSelection.rawValue, "request_member_selection"),
        (SparkToolName.fetchSleepDetails.rawValue, "fetch_sleep_details"),
        (SparkToolName.fetchStepDetails.rawValue, "fetch_step_details"),
        (SparkToolName.fetchEnergyDetails.rawValue, "fetch_energy_details"),
        (SparkToolName.fetchNutritionDetails.rawValue, "fetch_nutrition_details"),
        (SparkToolName.fetchWorkoutDetails.rawValue, "fetch_workout_details"),
    ]

    nonisolated static func mismatchedTools(prompt: String, schemaNames: [String]) -> [String] {
        let schemaSet = Set(schemaNames)
        return watchedTools.compactMap { entry in
            guard prompt.contains(entry.promptMarker) else { return nil }
            guard schemaSet.contains(entry.toolName) == false else { return nil }
            return entry.toolName
        }
    }
}
