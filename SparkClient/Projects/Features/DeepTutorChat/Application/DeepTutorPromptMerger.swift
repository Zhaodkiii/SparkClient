import Foundation

/// 合并智能体/会话人设与 DeepTutor capability 协议，不让人设被 capability 覆盖。
nonisolated enum DeepTutorPromptMerger {
    nonisolated static func buildSystemPrompt(
        context: DeepTutorResolvedModelContext,
        capability: DeepTutorCapability,
        conversationTitle: String,
        sessionPrompt: String?,
        healthPromptMode: DeepTutorHealthPromptMode,
        weatherPromptMode: DeepTutorWeatherPromptMode
    ) -> (systemPrompt: String, promptSource: DeepTutorPromptSource) {
        let protocolAddendum = DeepTutorPromptBuilder.buildProtocolAddendum(
            capability: capability,
            healthPromptMode: healthPromptMode,
            weatherPromptMode: weatherPromptMode
        )

        switch context.promptSource {
        case .agent:
            let persona = context.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let merged = [persona, protocolAddendum]
                .filter { $0.isEmpty == false }
                .joined(separator: "\n\n")
            return (merged, .agent)
        case .session:
            let session = sessionPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let merged = [session, protocolAddendum]
                .filter { $0.isEmpty == false }
                .joined(separator: "\n\n")
            return (merged, .session)
        case .smallTask, .deepTutorDefault:
            let built = DeepTutorPromptBuilder.build(
                capability: capability,
                conversationTitle: conversationTitle,
                rolePrompt: normalized(sessionPrompt),
                healthPromptMode: healthPromptMode,
                weatherPromptMode: weatherPromptMode
            )
            return (built.systemPrompt, .deepTutorDefault)
        }
    }

    nonisolated private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
