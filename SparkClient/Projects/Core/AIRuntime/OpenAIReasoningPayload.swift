import Foundation

// MARK: - 基础类型

enum ReasoningEffortLevel: String, Encodable {
    case minimal, low, medium, high, max

    static func fromTier(_ tier: Int) -> Self {
        switch tier {
        case 1:  return .low
        case 2:  return .medium
        case 3:  return .high
        default: return .minimal
        }
    }
}

enum ReasoningSwitch: String, Encodable {
    case enabled, disabled
}

// MARK: - Provider 能力模型

/// 厂商推理协议类型
enum ReasoningSupportType {
    case openAIStyle    // reasoning_effort（OpenAI / OpenRouter）
    case enableThinking // enable_thinking + thinking_budget（Qwen / 阿里云等）
    case deepSeekStyle  // thinking.type + reasoning_effort（high/max）；与 enable_thinking 协议不同
    case thinkingObject // thinking: { type, budget_tokens? }（Anthropic / Doubao / Zhipu …）
    case none           // 不支持推理控制
}

struct ProviderReasoningProfile {
    let supportType: ReasoningSupportType
    /// 关闭时是否必须显式下发 disabled（防止服务端默认开启）
    let requiresExplicitDisable: Bool
    /// 聊天 Composer：开启深度思考后是否展示强度档位菜单（与 `supportType != .none` 一致，可单独覆盖）
    let showsReasoningDepthMenu: Bool
    /// 聊天 Composer：强度菜单是否仅为 **high / max** 两档（与 `deepSeekStyle` 一致，可单独覆盖）
    let usesHighMaxReasoningEffortUI: Bool

    init(
        supportType: ReasoningSupportType,
        requiresExplicitDisable: Bool = false,
        showsReasoningDepthMenu: Bool? = nil,
        usesHighMaxReasoningEffortUI: Bool? = nil
    ) {
        self.supportType = supportType
        self.requiresExplicitDisable = requiresExplicitDisable
        self.showsReasoningDepthMenu = showsReasoningDepthMenu ?? (supportType != .none)
        self.usesHighMaxReasoningEffortUI = usesHighMaxReasoningEffortUI ?? (supportType == .deepSeekStyle)
    }
}

extension ProviderReasoningProfile {
    /// 未知厂商默认：thinkingObject 且不需要显式禁用
    static let `default` = ProviderReasoningProfile(
        supportType: .thinkingObject,
        requiresExplicitDisable: false
    )
}

/// 厂商能力配置表（未来可改为服务端下发）
struct ProviderRegistry {

    static let profiles: [String: ProviderReasoningProfile] = [

        // ✅ OpenAI 系（reasoning_effort）
        "OPENAI":     .init(supportType: .openAIStyle,    requiresExplicitDisable: false),
        "OPENROUTER": .init(supportType: .openAIStyle,    requiresExplicitDisable: false),

        // ❌ Google / XAI 不支持 reasoning 控制
        "GOOGLE": .init(supportType: .none, requiresExplicitDisable: false),
        "XAI":    .init(supportType: .none, requiresExplicitDisable: false),
        // ✅ Qwen / 阿里云（enable_thinking + thinking_budget）
        "MODELSCOPE":   .init(supportType: .enableThinking, requiresExplicitDisable: false),
        "SILICONCLOUD": .init(supportType: .enableThinking, requiresExplicitDisable: false),

        // ❌ 文心（没有统一 thinking 控制字段）
        "WENXIN": .init(supportType: .none, requiresExplicitDisable: false),

        // ✅ Anthropic（thinking: { type, budget_tokens }）
        "ANTHROPIC": .init(supportType: .thinkingObject, requiresExplicitDisable: false),

        // ✅ 智谱 GLM-5.2 / 5.1 / 5 / 4.7 默认开启 Thinking；关闭时必须显式传 disabled。
        // GLM thinking 只暴露开/关，不展示低/中/高强度档位。
        "ZHIPUAI":  .init( supportType: .thinkingObject, requiresExplicitDisable: true, showsReasoningDepthMenu: false),
        "MOONSHOT": .init(supportType: .thinkingObject, requiresExplicitDisable: false),
        "KIMI":     .init(supportType: .thinkingObject, requiresExplicitDisable: false),

        // ✅ 豆包（thinking: { type }，关闭时必须显式传 disabled）
        "DOUBAO": .init(supportType: .thinkingObject, requiresExplicitDisable: true),
        "QWEN":   .init(supportType: .thinkingObject, requiresExplicitDisable: true),


        // ✅ DeepSeek：thinking.type + reasoning_effort（high/max），非 enable_thinking / thinking_budget
        "DEEPSEEK": .init(supportType: .deepSeekStyle, requiresExplicitDisable: false),

        // ❌ Spark（讯飞自有网关，不支持客户端推理控制）
        "SPARK": .init(supportType: .none, requiresExplicitDisable: false),
    ]

    static func profile(for provider: String?) -> ProviderReasoningProfile {
        profiles[provider?.uppercased() ?? ""] ?? .default
    }

    /// 与聊天 Composer 对齐：是否展示思考强度菜单（未知厂商沿用 `ProviderReasoningProfile.default`）。
    static func showsReasoningDepthMenu(for provider: String?) -> Bool {
        profile(for: provider).showsReasoningDepthMenu
    }

    /// 与聊天 Composer 对齐：强度菜单是否为 high / max 两档。
    static func usesHighMaxReasoningEffortUI(for provider: String?) -> Bool {
        profile(for: provider).usesHighMaxReasoningEffortUI
    }
}

// MARK: - 推理决策

struct ReasoningDecision {
    let enabled: Bool
    let effort: ReasoningEffortLevel?
    let budget: Int?

    static let disabled = ReasoningDecision(enabled: false, effort: nil, budget: nil)
}

struct ReasoningDecider {

    static func decide(options: AIRuntimeReasoningOptions) -> ReasoningDecision {
        guard !options.usePromptFallback, options.isEnabled else { return .disabled }

        let effort = ReasoningEffortLevel.fromTier(options.effortTier)
        let budget: Int? = {
            switch options.effortTier {
            case 0, 1: return 1024
            case 2:    return 8192
            case 3:    return 16384
            default:   return nil
            }
        }()

        return ReasoningDecision(enabled: true, effort: effort, budget: budget)
    }
}

// MARK: - Payload 结构

/// thinking 对象（Anthropic 含 budget_tokens；其余厂商省略）
struct ThinkingPayload: Encodable {
    let type: ReasoningSwitch
    let budgetTokens: Int?

}

/// 各厂商推理扩展字段（合并到请求 body 顶层）
struct OpenAIReasoningExtras: Encodable {
    let reasoningEffort: ReasoningEffortLevel?  // openAIStyle
    let enableThinking: Bool?                   // enableThinking
    let thinkingBudget: Int?                    // enableThinking
    let thinking: ThinkingPayload?              // thinkingObject

}

// MARK: - 构建结果

struct ReasoningBuildResult {
    /// 需合并到请求 body 的推理字段；nil 表示该厂商无需任何推理扩展参数
    let extras: OpenAIReasoningExtras?

    static let empty = ReasoningBuildResult(extras: nil)
}

// MARK: - 主构建器

enum OpenAIReasoningBuilder {

    static func build(
        provider: String?,
        options: AIRuntimeReasoningOptions
    ) -> ReasoningBuildResult {
        let profile  = ProviderRegistry.profile(for: provider)
        let decision = ReasoningDecider.decide(options: options)

        switch profile.supportType {
        case .openAIStyle:
            return buildOpenAIStyle(decision: decision)
        case .enableThinking:
            return buildEnableThinking(decision: decision)
        case .deepSeekStyle:
            return buildDeepSeekStyle(decision: decision, effortTier: options.effortTier)
        case .thinkingObject:
            return buildThinkingObject(
                provider: provider,
                decision: decision,
                requiresExplicitDisable: profile.requiresExplicitDisable
            )
        case .none:
            return .empty
        }
    }
}

// MARK: - 构建实现

extension OpenAIReasoningBuilder {

    /// OpenAI / OpenRouter：reasoning_effort，关闭时不传字段
    private static func buildOpenAIStyle(
        decision: ReasoningDecision
    ) -> ReasoningBuildResult {
        guard decision.enabled else { return .empty }
        return ReasoningBuildResult(extras: OpenAIReasoningExtras(
            reasoningEffort: decision.effort,
            enableThinking: nil,
            thinkingBudget: nil,
            thinking: nil
        ))
    }

    /// Qwen / 阿里云：enable_thinking + thinking_budget，关闭时不传字段
    private static func buildEnableThinking(
        decision: ReasoningDecision
    ) -> ReasoningBuildResult {
        guard decision.enabled else { return .empty }
        return ReasoningBuildResult(extras: OpenAIReasoningExtras(
            reasoningEffort: nil,
            enableThinking: true,
            thinkingBudget: decision.budget,
            thinking: nil
        ))
    }

    /// DeepSeek：`thinking.type` + 顶层 `reasoning_effort`（仅 high / max）。
    /// 关闭时必须显式 `thinking: { type: disabled }`，否则服务端默认仍为开启。
    private static func buildDeepSeekStyle(
        decision: ReasoningDecision,
        effortTier: Int
    ) -> ReasoningBuildResult {
        let thinkingPayload = ThinkingPayload(
            type: decision.enabled ? .enabled : .disabled,
            budgetTokens: nil
        )
        // 文档：low/medium → high；最高档 → max
        let effort: ReasoningEffortLevel? = decision.enabled
            ? deepSeekReasoningEffort(for: effortTier)
            : nil
        return ReasoningBuildResult(extras: OpenAIReasoningExtras(
            reasoningEffort: effort,
            enableThinking: nil,
            thinkingBudget: nil,
            thinking: thinkingPayload
        ))
    }

    /// 与 DeepSeek 文档对齐：档位 3 映射为 max，其余在开启思考时映射为 high。
    private static func deepSeekReasoningEffort(for effortTier: Int) -> ReasoningEffortLevel {
        switch effortTier {
        case 3: return .max
        default: return .high
        }
    }

    /// Anthropic / Doubao / Zhipu 等：thinking: { type, budget_tokens? }
    /// - Anthropic：传 budget_tokens
    /// - 其他：省略 budget_tokens
    /// - requiresExplicitDisable（豆包）：关闭时仍下发 thinking.type = disabled
    private static func buildThinkingObject(
        provider: String?,
        decision: ReasoningDecision,
        requiresExplicitDisable: Bool
    ) -> ReasoningBuildResult {
        if !decision.enabled && !requiresExplicitDisable { return .empty }

        let isAnthropic = (provider?.uppercased() == "ANTHROPIC")
        let payload = ThinkingPayload(
            type: decision.enabled ? .enabled : .disabled,
            budgetTokens: isAnthropic ? decision.budget : nil
        )
        return ReasoningBuildResult(extras: OpenAIReasoningExtras(
            reasoningEffort: nil,
            enableThinking: nil,
            thinkingBudget: nil,
            thinking: payload
        ))
    }
}
