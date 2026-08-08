import Foundation

nonisolated enum DeepTutorHealthPromptMode: Equatable, Sendable {
    /// schema 含 request_member_selection：引导先选成员。
    case memberSelectionRequired
    /// schema 含健康 fetch 工具：成员已绑定，直接查数据。
    case healthFetchAvailable
    /// 本轮没有健康相关工具：禁止 prompt 假装可调用。
    case unavailable
}

nonisolated enum DeepTutorWeatherPromptMode: Equatable, Sendable {
    case cityPromptRequired
    case weatherFetchAvailable
    case unavailable
}

/// 按 DeepTutor capability 构造 system prompt（工具策略由 `DeepTutorToolPolicyResolver` 负责）。
enum DeepTutorPromptBuilder: Sendable {
    struct BuiltPrompt: Equatable, Sendable {
        let systemPrompt: String
    }

    nonisolated static func healthPromptMode(
        allowedToolNames: Set<String>,
        hasBoundMember: Bool
    ) -> DeepTutorHealthPromptMode {
        if hasBoundMember {
            return .healthFetchAvailable
        }
        if allowedToolNames.contains(SparkToolName.requestMemberSelection.rawValue) {
            return .memberSelectionRequired
        }
        let healthFetchTools: Set<String> = [
            SparkToolName.fetchSleepDetails.rawValue,
            SparkToolName.fetchStepDetails.rawValue,
            SparkToolName.fetchEnergyDetails.rawValue,
            SparkToolName.fetchNutritionDetails.rawValue,
            SparkToolName.fetchWorkoutDetails.rawValue,
            SparkToolName.makeNutritionData.rawValue,
        ]
        if allowedToolNames.isDisjoint(with: healthFetchTools) == false {
            return .healthFetchAvailable
        }
        return .unavailable
    }

    nonisolated static func weatherPromptMode(allowedToolNames: Set<String>) -> DeepTutorWeatherPromptMode {
        if allowedToolNames.contains(SparkToolName.askUserQuestion.rawValue),
           allowedToolNames.contains(SparkToolName.queryWeather.rawValue) {
            return .cityPromptRequired
        }
        let weatherTools: Set<String> = [
            SparkToolName.queryWeather.rawValue,
            SparkToolName.queryLocation.rawValue,
            SparkToolName.getCurrentLocation.rawValue,
        ]
        if allowedToolNames.isDisjoint(with: weatherTools) == false {
            return .weatherFetchAvailable
        }
        return .unavailable
    }

    nonisolated static func build(
        capability: DeepTutorCapability,
        conversationTitle: String,
        rolePrompt: String?,
        healthPromptMode: DeepTutorHealthPromptMode = .unavailable,
        weatherPromptMode: DeepTutorWeatherPromptMode = .unavailable
    ) -> BuiltPrompt {
        let titleContext: String
        if DeepTutorSessionTitle.isPlaceholder(conversationTitle) {
            titleContext = """
            You are DeepTutor, an educational AI tutor inside SparkClient.
            Respond in the same language as the user unless they ask otherwise.
            Use markdown for structured answers when helpful.
            """
        } else {
            titleContext = """
            You are DeepTutor, an educational AI tutor inside SparkClient.
            Current conversation title: \(conversationTitle).
            Respond in the same language as the user unless they ask otherwise.
            Use markdown for structured answers when helpful.
            """
        }

        let base = titleContext
        let capabilityPrompt = capabilityProtocol(
            capability: capability,
            healthPromptMode: healthPromptMode,
            weatherPromptMode: weatherPromptMode
        )

        let role = rolePrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let systemPrompt = [base, capabilityPrompt, role.isEmpty ? nil : "Additional instructions:\n\(role)"]
            .compactMap { $0 }
            .joined(separator: "\n\n")

        return BuiltPrompt(systemPrompt: systemPrompt)
    }

    /// DeepTutor capability / 工具协议追加段（不含默认 DeepTutor 人设），供智能体 Prompt 合并使用。
    nonisolated static func buildProtocolAddendum(
        capability: DeepTutorCapability,
        healthPromptMode: DeepTutorHealthPromptMode = .unavailable,
        weatherPromptMode: DeepTutorWeatherPromptMode = .unavailable
    ) -> String {
        let capabilityPrompt = capabilityProtocol(
            capability: capability,
            healthPromptMode: healthPromptMode,
            weatherPromptMode: weatherPromptMode
        )
        return """
        DeepTutorChat output protocol (must follow alongside your role instructions):
        \(capabilityPrompt)
        """
    }

    nonisolated private static func capabilityProtocol(
        capability: DeepTutorCapability,
        healthPromptMode: DeepTutorHealthPromptMode,
        weatherPromptMode: DeepTutorWeatherPromptMode
    ) -> String {
        switch capability {
        case .chat:
            let healthDataInstructions: String
            switch healthPromptMode {
            case .memberSelectionRequired:
                healthDataInstructions = """
                When querying personal or family health data without memberID in context:
                1. Call `request_member_selection` first.
                2. Do not ask users to type member IDs manually.
                3. Do not expose tool parameter schemas in the final answer.
                4. After member selection completes, continue with returned member_id for health tools.
                5. If the conversation already has a bound member, do not request member selection again unless the user explicitly asks to switch members.
                """
            case .healthFetchAvailable:
                healthDataInstructions = """
                Personal health data tools are available for the currently bound member.
                Use the appropriate fetch tool (for example `fetch_sleep_details` for sleep questions).
                If the user explicitly asks to switch members, call `request_member_selection` first.
                Do not expose tool parameter schemas in the final answer.
                """
            case .unavailable:
                healthDataInstructions = """
                You do not currently have access to personal health data tools (steps, sleep, nutrition, workouts) for this turn.
                If the user asks about their personal health data, explain that this capability is unavailable right now instead of claiming to call a tool.
                """
            }
            let weatherInstructions: String
            switch weatherPromptMode {
            case .cityPromptRequired:
                weatherInstructions = """
                Weather tools are available, but the user's city is unclear and location permission is unavailable.
                1. Call `ask_user` first to ask which city they want weather for.
                2. Do not invent coordinates or real-time weather.
                3. After the user answers, call `query_location` then `query_weather`.
                """
            case .weatherFetchAvailable:
                weatherInstructions = """
                Weather tools are available for this turn.
                1. If the user already named a city, call `query_location` first, then `query_weather` with returned coordinates.
                2. If the user asks for current-location weather and `get_current_location` is available, call it first, then `query_weather`.
                3. Never fabricate real-time weather. If tools fail or weather provider is unavailable, explain the failure clearly.
                4. References like "Apple Weather" or "苹果天气" are user context, not a signal to skip weather tools.
                """
            case .unavailable:
                weatherInstructions = """
                You do not currently have weather query tools for this turn.
                Do not claim to have checked live weather unless tool results are available.
                """
            }
            return """
            Mode: general tutoring chat.
            Explain clearly, cite reasoning steps, and ask clarifying questions when needed.
            You may call `ask_user` when you need structured user input.
            \(healthDataInstructions)
            \(weatherInstructions)
            """
        case .deepResearch:
            return """
            Mode: deep research.
            First outline a research plan with sections (understand, decompose, evidence, result), then expand each section.
            Prefer structured markdown headings. Summarize sources and assumptions explicitly.
            """
        case .deepQuestion:
            return """
            Mode: quiz / knowledge check.
            Default to multiple-choice questions. For a typical 3-question quiz produce:
            - 2 choice questions with options A-D
            - 1 concept (true/false) OR fill_in_blank question
            Do NOT default to short_answer / free-text questions unless the user explicitly asks for open-ended answers.
            Keep a brief introductory sentence in normal markdown prose only.
            Do NOT repeat full question bodies, options, or answers in the prose — they belong only in the structured block below.

            After the brief intro, append exactly one fenced code block tagged `quiz_json` containing ONLY valid JSON in this shape:
            {"results":[{"qa_pair":{"question_id":"q_1","question":"...","question_type":"choice|concept|fill_in_blank","options":{"A":"...","B":"...","C":"...","D":"...","correct_answer":"...","explanation":"...","difficulty":"easy|medium|hard","concentration":"..."}}]}

            Rules:
            - question_id must be stable strings like q_1, q_2, q_3.
            - Prefer question_type "choice" for most questions.
            - choice questions must include options A-D.
            - concept correct_answer must be "true" or "false".
            - fill_in_blank questions must include ____ in the question text.
            - Avoid question_type "short_answer" / "written" / "coding" unless explicitly requested.
            - Preferred output: append exactly one fenced code block tagged `quiz_json` containing ONLY valid JSON.
            - Acceptable fallback: output bare JSON `{"results":[{"qa_pair":{...}}]}` without repeating question bodies in prose.
            - The structured quiz payload must be the final content in the response.
            """
        case .mathAnimator:
            return """
            Mode: math animation / step-by-step demonstration.
            Break the solution into numbered steps suitable for animation.
            Use clear formulas and intermediate results.
            """
        case .visualize:
            return """
            Mode: visualization.
            Describe charts, diagrams, or structured visual specs the UI can render.
            Prefer bullet lists and labeled sections over vague prose.
            """
        case .masteryPath:
            return """
            Mode: mastery learning path.
            Assess prerequisites, propose a learning sequence, and adapt difficulty.
            """
        }
    }

    /// 兼容旧调用方：Bool 映射到三态中的 memberSelection / unavailable。
    nonisolated static func build(
        capability: DeepTutorCapability,
        conversationTitle: String,
        rolePrompt: String?,
        healthToolsAvailable: Bool
    ) -> BuiltPrompt {
        build(
            capability: capability,
            conversationTitle: conversationTitle,
            rolePrompt: rolePrompt,
            healthPromptMode: healthToolsAvailable ? .memberSelectionRequired : .unavailable
        )
    }
}
