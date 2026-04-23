import Foundation

// MARK: - 模型推理上下文（用于记录AI模型是否支持思考、深度推理能力）
/// 模型推理能力上下文（从内置模型列表 + 用户选择中解析得出）
/// 用于统一判断模型是否支持深度思考、是否可控制思考强度
struct ChatModelReasoningContext: Equatable, Sendable {
    /// 模型所属 provider id，例如 OPENAI、QWEN、LOCAL。
    var providerCompany: String?
    /// 是否支持推理/深度思考功能
    var supportsReasoning: Bool
    /// 是否可以控制推理强度/开关
    var reasoningControllable: Bool

    /// 未知模型的默认空实例
    static let unknown = ChatModelReasoningContext(
        providerCompany: nil,
        supportsReasoning: false,
        reasoningControllable: false
    )
}

// MARK: - AI 消息角色枚举
/// AI 对话消息角色（对应大模型API标准角色）
enum AIRuntimeRole: String, Codable, Sendable {
    case system      // 系统角色（设定AI行为）
    case user        // 用户角色
    case assistant   // AI助手角色
    case tool        // 工具调用返回角色
}

// MARK: - 多模态 content parts（OpenAI Chat Completions 兼容）
/// 单条 `image_url` 载荷（OpenAI Chat Completions 兼容；`detail` 仅部分厂商使用，如 XAI `high`）。
struct AIRuntimeImageURLPayload: Codable, Equatable, Sendable {
    let url: String
    /// 例如 `high`（XAI 多模态）；`nil` 时不编码该字段。
    let detail: String?

    init(url: String, detail: String? = nil) {
        self.url = url
        self.detail = detail
    }
}

/// 用户消息多模态片段（`type` + `text` 或 `image_url`）。
struct AIRuntimeContentPart: Codable, Equatable, Sendable {
    let type: String
    let text: String?
    let imageURL: AIRuntimeImageURLPayload?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    static func textPart(_ text: String) -> AIRuntimeContentPart {
        AIRuntimeContentPart(type: "text", text: text, imageURL: nil)
    }

    static func imagePart(url: String) -> AIRuntimeContentPart {
        AIRuntimeContentPart(type: "image_url", text: nil, imageURL: AIRuntimeImageURLPayload(url: url))
    }

    /// 与 `OpenAICompatibleTextGateway` 约定：内联 JPEG 的 **base64 原文**（不含 `data:` 前缀），由网关按厂商编码为最终 `image_url.url`。
    static let sparkInlineJPEGBase64Prefix = "spark:inline-jpeg-base64:"

    static func imageInlineJPEGBase64(_ jpegBase64: String) -> AIRuntimeContentPart {
        AIRuntimeContentPart(
            type: "image_url",
            text: nil,
            imageURL: AIRuntimeImageURLPayload(url: Self.sparkInlineJPEGBase64Prefix + jpegBase64, detail: nil)
        )
    }
}

// MARK: - AI 对话消息结构体
/// AI 运行时单条消息体（请求/响应通用）
struct AIRuntimeMessage: Codable, Equatable, Sendable {
    let role: AIRuntimeRole          // 消息角色
    let content: String?             // 消息文本内容
    /// 与 `content` 二选一：非 `nil` 时网关编码为 JSON 数组（多模态）。
    let contentParts: [AIRuntimeContentPart]?
    let toolCalls: [AIRuntimeToolCall]?  // 工具调用列表
    let toolCallID: String?          // 工具调用ID（用于关联响应）
    let name: String?                 // 工具/函数名称

    /// 构造方法
    init(
        role: AIRuntimeRole,
        content: String? = nil,
        contentParts: [AIRuntimeContentPart]? = nil,
        toolCalls: [AIRuntimeToolCall]? = nil,
        toolCallID: String? = nil,
        name: String? = nil
    ) {
        self.role = role
        self.content = content
        self.contentParts = contentParts
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
    }

    /// 本地 GGUF 等仅文本路径：从纯文本或多模态 parts 中提取可拼接的字符串。
    var normalizedTextContent: String? {
        if let contentParts, contentParts.isEmpty == false {
            let joined = contentParts.compactMap { part -> String? in
                guard part.type == "text" else { return nil }
                return part.text
            }.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        return content
    }
}

// MARK: - AI 工具参数属性（支持嵌套对象/数组）
/// AI工具调用的参数定义（对应OpenAI格式的 properties）
/// 支持嵌套 object / array，与项目内部工具定义对齐
final class AIRuntimeToolProperty: Codable, @unchecked Sendable {
    let type: String                          // 参数类型 string/object/array/number等
    let description: String                    // 参数描述（给AI看）
    let enumValues: [String]?                  // 枚举可选值
    let format: String?                        // 格式（如 int64, float）
    let objectProperties: [String: AIRuntimeToolProperty]?  // 对象嵌套属性
    let objectRequired: [String]?              // 对象必填字段
    let arrayItems: AIRuntimeToolProperty?     // 数组元素类型

    /// 构造方法
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

    /// JSON 编码键（映射后端字段名）
    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
        case format
        case objectProperties = "properties"
        case objectRequired = "required"
        case arrayItems = "items"
    }

    /// 自定义解码（默认值处理）
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

    /// 自定义编码
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

/// 遵守 Equatable 用于比较
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

// MARK: - AI 工具定义
/// AI可调用的工具完整定义
struct AIRuntimeToolDefinition: Codable, Equatable, Sendable {
    let name: String                              // 工具名称
    let summary: String                           // 工具描述/简介
    let properties: [String: AIRuntimeToolProperty]  // 入参结构
    let required: [String]                        // 必填参数名列表
}

// MARK: - AI 工具调用策略
/// 工具调用选择策略
enum AIRuntimeToolChoice: String, Codable, Sendable {
    case auto      // 自动判断是否调用
    case none      // 不使用任何工具
}

// MARK: - AI 工具调用记录
/// AI 实际发起的工具调用
struct AIRuntimeToolCall: Codable, Equatable, Sendable {
    let id: String            // 调用唯一ID
    let name: String          // 工具名称
    let arguments: String     // JSON格式的参数字符串
}

// MARK: - 推理控制选项
/// 统一的AI深度思考/推理控制配置（对接不同厂商模型）
struct AIRuntimeReasoningOptions: Equatable, Sendable {
    /// 是否启用推理思考
    var isEnabled: Bool
    /// 思考强度档位：0=不思考，1=低，2=中，3=高（与客户端UI档位一致）
    var effortTier: Int
    /// 原生API不支持思考时，是否用提示词降级实现
    var usePromptFallback: Bool

    /// 默认关闭思考
    static let disabled = AIRuntimeReasoningOptions(isEnabled: false, effortTier: 0, usePromptFallback: false)

    /// 构造方法（自动限制档位 0~3）
    init(isEnabled: Bool, effortTier: Int = 0, usePromptFallback: Bool = false) {
        self.isEnabled = isEnabled
        self.effortTier = min(max(effortTier, 0), 3)
        self.usePromptFallback = usePromptFallback
    }
}

// MARK: - AI 文本请求体
/// AI运行时 文本对话/推理请求结构体
struct AIRuntimeTextRequest: Sendable {
    let scenario: AIScenario                     // 业务场景
    let messages: [AIRuntimeMessage]             // 对话消息列表
    let tools: [AIRuntimeToolDefinition]         // 可用工具列表
    let toolChoice: AIRuntimeToolChoice          // 工具调用策略
    let reasoning: AIRuntimeReasoningOptions     // 推理控制配置
    let preferredModelName: String?              // 显式指定模型名（高于场景默认）
    let providerCompanyUppercased: String?       // provider id（服务内部填充，保留旧字段名以兼容调用链）
    let temperature: Double?                     // 线程级温度覆盖
    let topP: Double?                            // 线程级 top_p 覆盖
    let maxTokens: Int?                          // 线程级最大回复长度覆盖
    let cancellationToken: AIRuntimeCancellationToken? // 当前 AI 生成/抽取流程的协作式取消令牌

    /// 构造方法（提供默认值）
    init(
        scenario: AIScenario = .chat,
        messages: [AIRuntimeMessage],
        tools: [AIRuntimeToolDefinition] = [],
        toolChoice: AIRuntimeToolChoice = .auto,
        reasoning: AIRuntimeReasoningOptions = .disabled,
        preferredModelName: String? = nil,
        providerCompanyUppercased: String? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) {
        self.scenario = scenario
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.reasoning = reasoning
        self.preferredModelName = preferredModelName
        self.providerCompanyUppercased = providerCompanyUppercased
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.cancellationToken = cancellationToken
    }
}

// MARK: - AI 文本响应体
/// AI 文本对话完整响应
struct AIRuntimeTextResponse: Equatable, Sendable {
    let text: String                              // 最终回复文本（给用户看）
    let reasoningText: String?                    // 思考过程/推理链（部分模型返回）
    let model: String                             // 实际使用的模型名
    let promptTokens: Int?                        // 提示词token消耗
    let completionTokens: Int?                    // 回复token消耗
    let toolCalls: [AIRuntimeToolCall]            // 工具调用列表
    let finishReason: String?                     // 结束原因（stop/tool_call/length）

    /// 是否包含工具调用
    var hasToolCalls: Bool {
        !toolCalls.isEmpty
    }

    /// 构造方法
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

// MARK: - 工具调用增量数据
/// 流式返回时的工具调用增量片段
struct AIRuntimeToolCallDelta: Equatable, Sendable {
    let index: Int                // 第几个工具调用
    let id: String?               // 调用ID
    let name: String?             // 工具名
    let argumentsDelta: String?   // 参数增量片段
}

// MARK: - AI 流式事件枚举
/// AI流式响应的事件类型（用于实时接收文字/思考/工具调用）
enum AIRuntimeStreamEvent: Equatable, Sendable {
    case textDelta(String)            // 文本增量
    case reasoningDelta(String)       // 思考过程增量
    case toolCallDelta(AIRuntimeToolCallDelta)  // 工具调用增量
    case completed(AIRuntimeTextResponse)      // 最终完成响应
}

// MARK: - AI 运行时错误
/// AI模块统一错误类型（遵守LocalizedError）
enum AIRuntimeError: LocalizedError {
    case emptyMessages                // 消息列表为空
    case invalidResponse             // 响应格式非法无法解析
    case transport(URLError)          // 网络传输错误
    case server(statusCode: Int, message: String)  // 服务器返回错误
    case emptyOutput                  // 模型完成但没有返回可展示内容

    /// 错误本地化描述
    var errorDescription: String? {
        switch self {
        case .emptyMessages:
            return L10n.text("ai.error.empty_messages")
        case .invalidResponse:
            return L10n.text("ai.error.invalid_response")
        case .transport(let error):
            return error.localizedDescription
        case .server(_, let message):
            return message
        case .emptyOutput:
            return L10n.text("chat.error.empty_output")
        }
    }
}
