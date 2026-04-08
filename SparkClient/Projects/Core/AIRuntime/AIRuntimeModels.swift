import Foundation

/// Resolved model capabilities for reasoning (from `AllModels` + user selection).
struct ChatModelReasoningContext: Equatable, Sendable {
    /// Uppercased `AllModels.company`, e.g. `OPENAI`, `QWEN`.
    var providerCompany: String?
    var supportsReasoning: Bool
    var reasoningControllable: Bool

    static let unknown = ChatModelReasoningContext(
        providerCompany: nil,
        supportsReasoning: false,
        reasoningControllable: false
    )
}

enum AIRuntimeRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

struct AIRuntimeMessage: Codable, Equatable, Sendable {
    let role: AIRuntimeRole
    let content: String?
    let toolCalls: [AIRuntimeToolCall]?
    let toolCallID: String?
    let name: String?

    init(
        role: AIRuntimeRole,
        content: String? = nil,
        toolCalls: [AIRuntimeToolCall]? = nil,
        toolCallID: String? = nil,
        name: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
    }
}

/// OpenAI tools `parameters.properties` 条目；支持 object/array 嵌套（与 HealthClient `ZDKOpenChatTools` 对齐）。
final class AIRuntimeToolProperty: Codable, @unchecked Sendable {
    let type: String
    let description: String
    let enumValues: [String]?
    let format: String?
    let objectProperties: [String: AIRuntimeToolProperty]?
    let objectRequired: [String]?
    let arrayItems: AIRuntimeToolProperty?

    init(
        type: String = "string",
        description: String,
        enumValues: [String]? = nil,
        format: String? = nil,
        objectProperties: [String: AIRuntimeToolProperty]? = nil,
        objectRequired: [String]? = nil,
        arrayItems: AIRuntimeToolProperty? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.format = format
        self.objectProperties = objectProperties
        self.objectRequired = objectRequired
        self.arrayItems = arrayItems
    }

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
        case format
        case objectProperties = "properties"
        case objectRequired = "required"
        case arrayItems = "items"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "string"
        description = try c.decode(String.self, forKey: .description)
        enumValues = try c.decodeIfPresent([String].self, forKey: .enumValues)
        format = try c.decodeIfPresent(String.self, forKey: .format)
        objectProperties = try c.decodeIfPresent([String: AIRuntimeToolProperty].self, forKey: .objectProperties)
        objectRequired = try c.decodeIfPresent([String].self, forKey: .objectRequired)
        arrayItems = try c.decodeIfPresent(AIRuntimeToolProperty.self, forKey: .arrayItems)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(description, forKey: .description)
        try c.encodeIfPresent(enumValues, forKey: .enumValues)
        try c.encodeIfPresent(format, forKey: .format)
        try c.encodeIfPresent(objectProperties, forKey: .objectProperties)
        try c.encodeIfPresent(objectRequired, forKey: .objectRequired)
        try c.encodeIfPresent(arrayItems, forKey: .arrayItems)
    }
}

extension AIRuntimeToolProperty: Equatable {
    static func == (lhs: AIRuntimeToolProperty, rhs: AIRuntimeToolProperty) -> Bool {
        lhs.type == rhs.type
            && lhs.description == rhs.description
            && lhs.enumValues == rhs.enumValues
            && lhs.format == rhs.format
            && lhs.objectProperties == rhs.objectProperties
            && lhs.objectRequired == rhs.objectRequired
            && lhs.arrayItems == rhs.arrayItems
    }
}

struct AIRuntimeToolDefinition: Codable, Equatable, Sendable {
    let name: String
    let summary: String
    let properties: [String: AIRuntimeToolProperty]
    let required: [String]
}

enum AIRuntimeToolChoice: String, Codable, Sendable {
    case auto
    case none
}

struct AIRuntimeToolCall: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let arguments: String
}

/// Unified reasoning controls for gateways (mapped per provider).
struct AIRuntimeReasoningOptions: Equatable, Sendable {
    /// User asked for “deep thinking” / reasoning (already gated by UI + model caps).
    var isEnabled: Bool
    /// 0 = minimal（不思考），1 = low，2 = medium，3 = high（与 HealthClient 思考长度档位一致）。
    var effortTier: Int
    /// When native API params are unavailable, append a system prompt instead.
    var usePromptFallback: Bool

    static let disabled = AIRuntimeReasoningOptions(isEnabled: false, effortTier: 0, usePromptFallback: false)

    init(isEnabled: Bool, effortTier: Int = 0, usePromptFallback: Bool = false) {
        self.isEnabled = isEnabled
        self.effortTier = min(max(effortTier, 0), 3)
        self.usePromptFallback = usePromptFallback
    }
}

struct AIRuntimeTextRequest: Sendable {
    let scenario: AIScenario
    let messages: [AIRuntimeMessage]
    let tools: [AIRuntimeToolDefinition]
    let toolChoice: AIRuntimeToolChoice
    let reasoning: AIRuntimeReasoningOptions
    /// Provider tag from `AllModels.company` (filled by `AIRuntimeService` when calling remote gateway).
    let providerCompanyUppercased: String?

    init(
        scenario: AIScenario = .chat,
        messages: [AIRuntimeMessage],
        tools: [AIRuntimeToolDefinition] = [],
        toolChoice: AIRuntimeToolChoice = .auto,
        reasoning: AIRuntimeReasoningOptions = .disabled,
        providerCompanyUppercased: String? = nil
    ) {
        self.scenario = scenario
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.reasoning = reasoning
        self.providerCompanyUppercased = providerCompanyUppercased
    }
}

struct AIRuntimeTextResponse: Equatable, Sendable {
    /// Final assistant answer (user-facing).
    let text: String
    /// Optional chain-of-thought / reasoning channel from the provider stream.
    let reasoningText: String?
    let model: String
    let promptTokens: Int?
    let completionTokens: Int?
    let toolCalls: [AIRuntimeToolCall]
    let finishReason: String?

    var hasToolCalls: Bool {
        toolCalls.isEmpty == false
    }

    init(
        text: String,
        reasoningText: String? = nil,
        model: String,
        promptTokens: Int?,
        completionTokens: Int?,
        toolCalls: [AIRuntimeToolCall],
        finishReason: String?
    ) {
        self.text = text
        self.reasoningText = reasoningText
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.toolCalls = toolCalls
        self.finishReason = finishReason
    }
}

struct AIRuntimeToolCallDelta: Equatable, Sendable {
    let index: Int
    let id: String?
    let name: String?
    let argumentsDelta: String?
}

enum AIRuntimeStreamEvent: Equatable, Sendable {
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(AIRuntimeToolCallDelta)
    case completed(AIRuntimeTextResponse)
}

enum AIRuntimeError: LocalizedError {
    case emptyMessages
    case invalidResponse
    case transport(URLError)
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .emptyMessages:
            return "消息为空，无法调用 AI 推理。"
        case .invalidResponse:
            return "AI 返回结果不可解析。"
        case .transport(let error):
            return error.localizedDescription
        case .server(_, let message):
            return message
        }
    }
}
