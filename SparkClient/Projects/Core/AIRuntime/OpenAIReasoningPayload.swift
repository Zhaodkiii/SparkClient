import Foundation

struct ReasoningThinkTogglePayload: Encodable {
    let type: String
}

/// Maps unified `AIRuntimeReasoningOptions` + provider company to OpenAI-compatible request extras (and optional `/think` suffix).
enum OpenAIReasoningPayload {
    struct Extras: Encodable {
        let reasoningEffort: String?
        let enableThinking: Bool?
        let thinkingBudget: Int?
        let think: ReasoningThinkTogglePayload?
        let thinking: ReasoningThinkTogglePayload?

        enum CodingKeys: String, CodingKey {
            case reasoningEffort = "reasoning_effort"
            case enableThinking = "enable_thinking"
            case thinkingBudget = "thinking_budget"
            case think
            case thinking
        }

        init(
            reasoningEffort: String?,
            enableThinking: Bool?,
            thinkingBudget: Int?,
            thinkType: String?,
            thinkingType: String?
        ) {
            self.reasoningEffort = reasoningEffort
            self.enableThinking = enableThinking
            self.thinkingBudget = thinkingBudget
            self.think = thinkType.map { ReasoningThinkTogglePayload(type: $0) }
            self.thinking = thinkingType.map { ReasoningThinkTogglePayload(type: $0) }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
            try c.encodeIfPresent(enableThinking, forKey: .enableThinking)
            try c.encodeIfPresent(thinkingBudget, forKey: .thinkingBudget)
            try c.encodeIfPresent(think, forKey: .think)
            try c.encodeIfPresent(thinking, forKey: .thinking)
        }
    }

    /// When `true`, caller should append ` /think` or ` /no_think` to the last **user** message instead of using native fields.
    static func build(
        providerUppercased: String?,
        options: AIRuntimeReasoningOptions
    ) -> (extras: Extras?, useThinkSuffix: Bool, thinkSuffixEnabled: Bool) {
        let p = providerUppercased?.uppercased() ?? ""
        // 走 system prompt 兜底时不上送原生 reasoning 字段（与 `ChatOrchestrator` 一致）。
        if options.usePromptFallback {
            return (nil, false, false)
        }

        let tier = options.effortTier

        switch p {
        case "DOUBAO":
            // 豆包：`thinking.type` = enabled/disabled；开启时 `reasoning_effort` = minimal | low | medium | high（minimal 为不思考）。
            return buildDoubaoExtras(tier: tier, options: options)

        case "OPENAI", "GOOGLE", "XAI":
            guard options.isEnabled else { return (nil, false, false) }
            let effort = reasoningEffortMinimalLowMediumHigh(tier: tier)
            return (Extras(reasoningEffort: effort, enableThinking: nil, thinkingBudget: nil, thinkType: nil, thinkingType: nil), false, false)

        case "OPENROUTER":
            guard options.isEnabled else { return (nil, false, false) }
            if tier >= 3 {
                let budget = 16384
                return (Extras(reasoningEffort: nil, enableThinking: nil, thinkingBudget: budget, thinkType: nil, thinkingType: nil), false, false)
            }
            let effort: String? = {
                switch tier {
                case 0, 1: return "low"
                case 2: return "medium"
                default: return "high"
                }
            }()
            return (Extras(reasoningEffort: effort, enableThinking: nil, thinkingBudget: nil, thinkType: nil, thinkingType: nil), false, false)

        case "QWEN", "MODELSCOPE", "SILICONCLOUD", "WENXIN":
            guard options.isEnabled else { return (nil, false, false) }
            let budget: Int? = {
                switch tier {
                case 0, 1: return 1024
                case 2: return 8192
                case 3: return 16384
                default: return 1024
                }
            }()
            return (Extras(reasoningEffort: nil, enableThinking: true, thinkingBudget: budget, thinkType: nil, thinkingType: nil), false, false)

        case "ANTHROPIC":
            let thinkType = options.isEnabled ? "enabled" : "disabled"
            return (Extras(reasoningEffort: nil, enableThinking: nil, thinkingBudget: nil, thinkType: thinkType, thinkingType: nil), false, false)

        case "ZHIPUAI", "HANLIN":
            let thinkingType = options.isEnabled ? "enabled" : "disabled"
            return (Extras(reasoningEffort: nil, enableThinking: nil, thinkingBudget: nil, thinkType: nil, thinkingType: thinkingType), false, false)

        default:
            guard options.isEnabled else { return (nil, false, false) }
            return (nil, true, true)
        }
    }

    /// 豆包：关闭深度思考时仍上送 `thinking.type=disabled`，避免沿用服务端默认开启。
    private static func buildDoubaoExtras(
        tier: Int,
        options: AIRuntimeReasoningOptions
    ) -> (Extras?, Bool, Bool) {
        if options.isEnabled == false {
            let extras = Extras(
                reasoningEffort: nil,
                enableThinking: nil,
                thinkingBudget: nil,
                thinkType: nil,
                thinkingType: "disabled"
            )
            return (extras, false, false)
        }
        let effort = reasoningEffortMinimalLowMediumHigh(tier: tier)
        let extras = Extras(
            reasoningEffort: effort,
            enableThinking: nil,
            thinkingBudget: nil,
            thinkType: nil,
            thinkingType: "enabled"
        )
        return (extras, false, false)
    }

    /// 与 HealthClient `ZDKOpenChatStore+Thinking` 对齐：minimal / low / medium / high。
    private static func reasoningEffortMinimalLowMediumHigh(tier: Int) -> String {
        switch tier {
        case 0: return "minimal"
        case 1: return "low"
        case 2: return "medium"
        case 3: return "high"
        default: return "minimal"
        }
    }

    static func patchMessagesThinkSuffix(
        _ messages: [AIRuntimeMessage],
        thinkSuffixEnabled: Bool
    ) -> [AIRuntimeMessage] {
        guard let idx = messages.lastIndex(where: { $0.role == .user }),
              var content = messages[idx].content,
              content.isEmpty == false
        else {
            return messages
        }
        if content.contains("/think") || content.contains("/no_think") {
            return messages
        }
        content += thinkSuffixEnabled ? " /think" : " /no_think"
        var out = messages
        let m = messages[idx]
        out[idx] = AIRuntimeMessage(
            role: m.role,
            content: content,
            toolCalls: m.toolCalls,
            toolCallID: m.toolCallID,
            name: m.name
        )
        return out
    }
}
