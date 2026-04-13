import Foundation

/// 推理思考开关的载体结构体，用于标记思考类型
struct ReasoningThinkTogglePayload: Encodable {
    let type: String
}

/// 将统一的推理配置（AIRuntimeReasoningOptions）+ 厂商类型
/// 映射为各 AI 厂商兼容的 OpenAI 风格请求参数（支持原生思考字段 或 /think 后缀）
enum OpenAIReasoningPayload {

    /// 各厂商通用的「深度思考」扩展参数
    /// 不同厂商使用不同字段：reasoning_effort / enable_thinking / thinking / think 等
    struct Extras: Encodable {
        let reasoningEffort: String?       // 推理强度：low/medium/high/minimal
        let enableThinking: Bool?          // 是否开启思考
        let thinkingBudget: Int?            // 思考 Token 预算
        let think: ReasoningThinkTogglePayload?   // Anthropic 系思考开关
        let thinking: ReasoningThinkTogglePayload? // 智谱/翰林/豆包 系思考开关

        /// JSON 映射键（与厂商 API 字段严格对齐）
        enum CodingKeys: String, CodingKey {
            case reasoningEffort = "reasoning_effort"
            case enableThinking = "enable_thinking"
            case thinkingBudget = "thinking_budget"
            case think
            case thinking
        }

        /// 构造扩展参数
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

        /// 自定义编码：只编码存在值的字段，避免 null
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
            try c.encodeIfPresent(enableThinking, forKey: .enableThinking)
            try c.encodeIfPresent(thinkingBudget, forKey: .thinkingBudget)
            try c.encodeIfPresent(think, forKey: .think)
            try c.encodeIfPresent(thinking, forKey: .thinking)
        }
    }

    // MARK: - 主构建方法
    /// 根据 AI 厂商 + 推理配置，生成对应厂商的思考参数
    /// 返回：(扩展参数, 是否使用 /think 后缀, 是否开启后缀)
    static func build(
        providerUppercased: String?,
        options: AIRuntimeReasoningOptions
    ) -> (extras: Extras?, useThinkSuffix: Bool, thinkSuffixEnabled: Bool) {
        let p = providerUppercased?.uppercased() ?? ""
        
        // 使用系统提示词兜底时，不上送原生推理字段（与 ChatOrchestrator 逻辑保持一致）
        if options.usePromptFallback {
            return (nil, false, false)
        }

        let tier = options.effortTier

        switch p {
        case "DOUBAO":
            // 豆包：thinking.type = enabled/disabled；开启时带 reasoning_effort
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
            // Anthropic 使用 think 字段：enabled / disabled
            let thinkType = options.isEnabled ? "enabled" : "disabled"
            return (Extras(reasoningEffort: nil, enableThinking: nil, thinkingBudget: nil, thinkType: thinkType, thinkingType: nil), false, false)

        case "ZHIPUAI", "HANLIN", "MOONSHOT", "KIMI":
            // 智谱、翰林、Moonshot/Kimi（如 kimi-k2.5）等：thinking.type = enabled / disabled
            let thinkingType = options.isEnabled ? "enabled" : "disabled"
            return (Extras(reasoningEffort: nil, enableThinking: nil, thinkingBudget: nil, thinkType: nil, thinkingType: thinkingType), false, false)

        case "SPARK", "DEEPSEEK":
            // 自有网关与 DeepSeek：维持仅 /think 后缀，不上送 thinking 对象，避免与既有契约冲突
            guard options.isEnabled else { return (nil, false, false) }
            return (nil, true, true)

        default:
            // 其余 OpenAI 兼容厂商：关闭深度思考时显式 thinking.type=disabled，避免部分模型默认开启链式思考；开启时沿用 /think 后缀
            guard options.isEnabled else {
                return (
                    Extras(
                        reasoningEffort: nil,
                        enableThinking: nil,
                        thinkingBudget: nil,
                        thinkType: nil,
                        thinkingType: "disabled"
                    ),
                    false,
                    false
                )
            }
            return (nil, true, true)
        }
    }

    // MARK: - 豆包专用构建
    /// 豆包专属思考参数构建
    /// 关闭时必须显式传 thinking.type = disabled，防止服务端默认开启
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

    // MARK: - 工具方法
    /// 将思考等级 tier 映射为标准字符串：minimal / low / medium / high
    private static func reasoningEffortMinimalLowMediumHigh(tier: Int) -> String {
        switch tier {
        case 0: return "minimal"
        case 1: return "low"
        case 2: return "medium"
        case 3: return "high"
        default: return "minimal"
        }
    }

    /// 为最后一条 user 消息自动追加 /think 或 /no_think 后缀
    /// 用于不支持原生思考字段的厂商兼容
    static func patchMessagesThinkSuffix(
        _ messages: [AIRuntimeMessage],
        thinkSuffixEnabled: Bool
    ) -> [AIRuntimeMessage] {
        // 找到最后一条 user 消息
        guard let idx = messages.lastIndex(where: { $0.role == .user }),
              var content = messages[idx].content,
              content.isEmpty == false
        else {
            return messages
        }
        
        // 已存在后缀则不处理
        if content.contains("/think") || content.contains("/no_think") {
            return messages
        }
        
        // 追加思考后缀
        content += thinkSuffixEnabled ? " /think" : " /no_think"
        
        // 构造新消息数组
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
