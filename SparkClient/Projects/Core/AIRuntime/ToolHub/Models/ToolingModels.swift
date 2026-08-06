import Foundation

// MARK: - 工具审计相关
/// 工具执行审计状态
enum ToolAuditStatus: String, Codable, Sendable {
    case success    // 执行成功
    case denied     // 执行被拒绝
    case failed     // 执行失败
}

/// 工具执行审计事件（用于记录工具调用日志）
struct ToolAuditEvent: Identifiable, Codable, Sendable {
    let id: UUID                    // 唯一标识
    let toolName: String            // 工具名称
    let memberID: Int?              // 关联成员ID（可选）
    let inputSummary: String        // 输入内容摘要
    let outputSummary: String       // 输出内容摘要
    let status: ToolAuditStatus     // 执行状态
    let createdAt: Date             // 创建时间

    /// 初始化方法（提供默认值）
    init(
        id: UUID = UUID(),
        toolName: String,
        memberID: Int?,
        inputSummary: String,
        outputSummary: String,
        status: ToolAuditStatus,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.memberID = memberID
        self.inputSummary = inputSummary
        self.outputSummary = outputSummary
        self.status = status
        self.createdAt = createdAt
    }
}

// MARK: - 工具 UI 副作用（由 MessageRunActor 串行落库，不经过 Task 异步发卡）
enum ToolSideEffect: Sendable {
    case healthResourceReference(resourceType: String, resourceID: Int, memberID: Int)
    case knowledgeCards([ChatKnowledgeCard])
    case taskCards([TaskCard])
    case captureCard(ChatCaptureMessageCardPayload)
    case workoutVisualization(ChatHealthWorkoutModel)
    case sleepVisualization(ChatHealthSleepModel)
    case nutritionCards([ChatNutritionCardPayload])
    case medicalRiskNotice(ChatMedicalRiskNoticePayload)
    case externalConnectorRichBlocks([ChatMessageBlock])
    case structuredHealthCardsPending
    case structuredHealthCardsReady(StructuredHealthCardsBlob)
    case structuredHealthCardsFailed(message: String?)
    case timelineNotice(text: String)
}

// MARK: - 工具执行结果
/// 工具执行结果模型
struct ToolExecutionResult: Sendable {
    let toolName: String                // 执行的工具名称
    let outputText: String              // 工具输出文本
    let sensitive: Bool                 // 是否包含敏感数据
    let shouldBypassModel: Bool         // 是否跳过模型直接返回结果
    let isAwaitingUserInput: Bool       // 是否等待用户输入
    let resolvedMemberID: Int?          // 已解析的成员ID
    let toolCallID: String?             // 模型本轮 tool_call id，用于消息块锚定
    /// 展示块锚定的 tool_call id；默认由 Hub 从 pendingToolCallID 填充，工具可覆盖。
    let anchorToolCallID: String?
    /// 工具执行侧归一化后的调用参数（供工具详情 Sheet 展示，与模型原始 JSON 字符串解耦）。
    let arguments: [String: String]?
    /// 需在助手消息时间线落库的 UI 副作用，由 ChatOrchestrator 经 MessageRunActor 串行写入。
    let sideEffects: [ToolSideEffect]

    /// 初始化方法
    init(
        toolName: String,
        outputText: String,
        sensitive: Bool,
        shouldBypassModel: Bool,
        isAwaitingUserInput: Bool = false,
        resolvedMemberID: Int? = nil,
        toolCallID: String? = nil,
        anchorToolCallID: String? = nil,
        arguments: [String: String]? = nil,
        sideEffects: [ToolSideEffect] = []
    ) {
        self.toolName = toolName
        self.outputText = outputText
        self.sensitive = sensitive
        self.shouldBypassModel = shouldBypassModel
        self.isAwaitingUserInput = isAwaitingUserInput
        self.resolvedMemberID = resolvedMemberID
        self.toolCallID = toolCallID
        self.anchorToolCallID = anchorToolCallID
        self.arguments = arguments
        self.sideEffects = sideEffects
    }

    func withToolCallID(_ toolCallID: String?) -> ToolExecutionResult {
        ToolExecutionResult(
            toolName: toolName,
            outputText: outputText,
            sensitive: sensitive,
            shouldBypassModel: shouldBypassModel,
            isAwaitingUserInput: isAwaitingUserInput,
            resolvedMemberID: resolvedMemberID,
            toolCallID: toolCallID,
            anchorToolCallID: anchorToolCallID ?? toolCallID,
            arguments: arguments,
            sideEffects: sideEffects
        )
    }

    func withAnchorToolCallID(_ pendingAnchor: String?) -> ToolExecutionResult {
        ToolExecutionResult(
            toolName: toolName,
            outputText: outputText,
            sensitive: sensitive,
            shouldBypassModel: shouldBypassModel,
            isAwaitingUserInput: isAwaitingUserInput,
            resolvedMemberID: resolvedMemberID,
            toolCallID: toolCallID,
            anchorToolCallID: anchorToolCallID ?? pendingAnchor,
            arguments: arguments,
            sideEffects: sideEffects
        )
    }

    /// 若结果未携带调用参数，则填入本次 invocation 参数（供工具详情 Sheet 展示）。
    func withInvocationArgumentsIfMissing(_ invocationArguments: [String: String]) -> ToolExecutionResult {
        guard invocationArguments.isEmpty == false else { return self }
        if let arguments, arguments.isEmpty == false {
            return self
        }
        return ToolExecutionResult(
            toolName: toolName,
            outputText: outputText,
            sensitive: sensitive,
            shouldBypassModel: shouldBypassModel,
            isAwaitingUserInput: isAwaitingUserInput,
            resolvedMemberID: resolvedMemberID,
            toolCallID: toolCallID,
            anchorToolCallID: anchorToolCallID,
            arguments: invocationArguments,
            sideEffects: sideEffects
        )
    }
}

// MARK: - 数据敏感度与策略
/// 工具数据敏感度等级
enum ToolDataSensitivity: String, Codable, Sendable {
    case none        // 无敏感
    case personal    // 个人数据
    case sensitive   // 敏感数据
    case regulated   // 受监管数据（如健康）

    /// 是否需要模型授权同意
    var requiresModelConsent: Bool {
        switch self {
        case .none:
            return false
        case .personal, .sensitive, .regulated:
            return true
        }
    }
}

/// 工具数据分类
enum ToolDataCategory: String, Codable, Sendable {
    case health      // 健康
    case member      // 成员
    case location    // 位置
    case memory      // 记忆
    case knowledge   // 知识
    case calendar    // 日历
    case publicWeb   // 公共网络
    case ui          // UI交互
    case system      // 系统
}

/// 工具数据出口策略（数据能否外传）
enum ToolEgressPolicy: String, Codable, Sendable {
    case allow           // 允许外传
    case requireConsent   // 需要用户授权
    case localOnly        // 仅本地使用
}

// MARK: - 工具调用基础模型
/// 工具中心执行结果
enum ToolHubResult: Sendable {
    case none                    // 无执行
    case executed(ToolExecutionResult)  // 已执行，返回结果
}

/// 工具调用信息
struct ToolInvocation: Sendable {
    let name: String              // 工具名
    let arguments: [String: String] // 调用参数
}

/// 工具执行上下文（环境信息）
struct ToolExecutionContext: Sendable {
    let memberID: Int?                    // 当前成员ID
    let locale: Locale                    // 区域语言
    let assistantMessageClientID: UUID?   // 助手消息客户端ID
    let threadID: UUID?                   // 会话ID
    let pendingToolCallID: String?        // 待处理工具调用ID
    let pendingResumeMessages: [AIRuntimeMessage] // 待恢复消息
    let providerCompany: String?          // 服务提供方公司
    let modelName: String?                // 使用模型名称
    let endpoint: String?                 // 接口地址
    let privacyPolicyURL: URL?            // 隐私政策链接
    /// DeepTutor 等场景：在消息内卡片收集追问，不弹通用 sheet。
    let preferInlineAskUser: Bool
    /// DeepTutor 等场景：在消息内卡片收集成员选择，不弹通用 sheet。
    let preferInlineMemberSelection: Bool

    init(
        memberID: Int?,
        locale: Locale,
        assistantMessageClientID: UUID? = nil,
        threadID: UUID? = nil,
        pendingToolCallID: String? = nil,
        pendingResumeMessages: [AIRuntimeMessage] = [],
        providerCompany: String? = nil,
        modelName: String? = nil,
        endpoint: String? = nil,
        privacyPolicyURL: URL? = nil,
        preferInlineAskUser: Bool = false,
        preferInlineMemberSelection: Bool = false
    ) {
        self.memberID = memberID
        self.locale = locale
        self.assistantMessageClientID = assistantMessageClientID
        self.threadID = threadID
        self.pendingToolCallID = pendingToolCallID
        self.pendingResumeMessages = pendingResumeMessages
        self.providerCompany = providerCompany
        self.modelName = modelName
        self.endpoint = endpoint
        self.privacyPolicyURL = privacyPolicyURL
        self.preferInlineAskUser = preferInlineAskUser
        self.preferInlineMemberSelection = preferInlineMemberSelection
    }
}

/// 工具定义（描述信息）
struct ToolDefinition: Sendable {
    let name: String      // 工具名
    let summary: String   // 工具摘要
    let usage: String     // 使用说明
}

// MARK: - 工具枚举（核心）
/// Spark 平台所有可用工具枚举。
///
/// **新增或重命名工具时须同步（保持 rawValue 一致）：**
/// 1. `SparkService/ai_config/models.py` — `SparkToolName`
/// 2. `ToolHub.swift` — `toolProperties` / `toolRequiredFields` / `execute`
/// 3. `ToolHub/Executors/` — 工具实现
/// 4. `Projects/App/Resources/en.lproj/ToolPrompts.strings`（及 zh-Hans、zh-Hant）— `tool.summary.*` / `tool.param.*`
/// 5. `Projects/App/Resources/en.lproj/Localizable.strings`（及 zh-Hans）— `ai_settings.tools.*`
/// 6. `OnboardingAgentSetupViewModel.healthTools` 等默认工具白名单（按需）
nonisolated enum SparkToolName: String, CaseIterable {
    // MARK: 健康类（Apple Health / 结构化卡片 / 问报告 M11）
    case fetchStepDetails            = "fetch_step_details"             // 获取步数详情
    case fetchEnergyDetails          = "fetch_energy_details"           // 获取能量详情
    case fetchNutritionDetails       = "fetch_nutrition_details"        // 获取营养详情
    case makeNutritionData           = "make_nutrition_data"            // 生成营养数据
    case showMedicalRiskNotice       = "show_medical_risk_notice"       // 医疗风险提示卡片
    case fetchSleepDetails           = "fetch_sleep_details"            // 获取睡眠详情
    case fetchWorkoutDetails         = "fetch_workout_details"          // 获取运动详情
    case generateStructuredHealthCard = "generate_structured_health_card" // 生成结构化健康卡片（后台抽取）
    case listMemberHealthSources     = "list_member_health_sources"      // 问报告：检索成员健康资料候选
    case getHealthResourceReference  = "get_health_resource_reference"   // 问报告：校验并返回单条资料引用
    case getHealthResourceContext    = "get_health_resource_context"     // 问报告：获取单条资料解读上下文（M8）

    // MARK: 知识类
    case searchKnowledgeBag          = "search_knowledge_bag"           // 搜索知识包
    case createKnowledgeDocument     = "create_knowledge_document"      // 创建知识文档
    
    // MARK: 日历类
    case searchCalendarAndReminders  = "search_calendar_and_reminders"  // 搜索日历和提醒
    case writeSystemEvent            = "write_system_event"              // 写入系统事件
    
    // MARK: 位置类
    case queryLocation               = "query_location"                 // 查询位置
    case getCurrentLocation          = "get_current_location"           // 获取当前位置
    case searchNearbyLocations       = "search_nearby_locations"        // 搜索附近位置
    case getRoute                    = "get_route"                       // 获取路线
    case queryWeather                = "query_weather"                  // 查询天气
    
    // MARK: 记忆类
    case saveMemory                  = "save_memory"                     // 保存记忆
    case retrieveMemory              = "retrieve_memory"                // 检索记忆
    case updateMemory                = "update_memory"                   // 更新记忆
    
    // MARK: UI 交互类
    case generateChatTitle           = "generate_chat_title"            // 生成聊天标题
    case showCustomMessageCard       = "show_custom_message_card"        // 显示自定义消息卡片
    case askUserQuestion             = "ask_user_question"              // 向用户提问
    
    // MARK: 成员类
    case getCurrentMember            = "get_current_member"              // 获取当前成员
    case requestMemberSelection      = "request_member_selection"        // 请求选择成员
    case switchMember                = "switch_member"                   // 切换成员
    case findMember                  = "find_member"                     // 查找成员
    case queryMemberProfile          = "query_member_profile"            // 查询成员资料
    
    // MARK: 网络类
    case searchOnline                = "search_online"                   // 在线搜索
    case readWebPage                 = "read_web_page"                   // 读取网页
    case searchArxivPapers           = "search_arxiv_papers"             // 搜索论文
    case extractRemoteFileContent    = "extract_remote_file_content"    // 提取远程文件内容
    
    // MARK: 系统 / 画布 / 任务类
    case createCanvas                = "create_canvas"                   // 创建画布
    case editCanvas                  = "edit_canvas"                     // 编辑画布
    case queryTasksByMember          = "query_tasks_by_member"           // 查询成员任务
    case generateTask                = "generate_task"                  // 生成任务

    /// 所有工具原始值集合（自动生成）
    static var all: [String] { allCases.map(\.rawValue) }
}

// MARK: - 工具属性扩展（分类/敏感度/出口策略）
extension SparkToolName {
    /// 工具对应的数据分类
    var dataCategory: ToolDataCategory {
        switch self {
        case .fetchStepDetails, .fetchEnergyDetails, .fetchNutritionDetails, .makeNutritionData,
             .fetchSleepDetails, .fetchWorkoutDetails, .generateStructuredHealthCard,
             .listMemberHealthSources, .getHealthResourceReference, .getHealthResourceContext:
            return .health
        case .getCurrentMember, .requestMemberSelection, .switchMember, .findMember, .queryMemberProfile:
            return .member
        case .queryLocation, .getCurrentLocation, .searchNearbyLocations, .getRoute, .queryWeather:
            return .location
        case .saveMemory, .retrieveMemory, .updateMemory:
            return .memory
        case .searchKnowledgeBag, .createKnowledgeDocument:
            return .knowledge
        case .searchCalendarAndReminders, .writeSystemEvent:
            return .calendar
        case .searchOnline, .readWebPage, .searchArxivPapers, .extractRemoteFileContent:
            return .publicWeb
        case .showCustomMessageCard, .askUserQuestion, .showMedicalRiskNotice:
            return .ui
        case .generateChatTitle, .createCanvas, .editCanvas, .queryTasksByMember, .generateTask:
            return .system
        }
    }

    /// 工具声明的数据敏感度
    var declaredSensitivity: ToolDataSensitivity {
        switch dataCategory {
        case .health:
            return .regulated       // 健康属于受监管数据
        case .member, .location, .memory, .calendar:
            return .personal        // 个人相关数据
        case .knowledge:
            return .sensitive       // 敏感知识数据
        case .publicWeb, .ui, .system:
            return .none            // 无敏感数据
        }
    }

    /// 工具数据出口策略
    var egressPolicy: ToolEgressPolicy {
        declaredSensitivity.requiresModelConsent ? .requireConsent : .allow
    }
}

// MARK: - 工具提问交互模型
/// 选择模式：单选/多选
enum ChatQuestionSelectionMode: String, Codable, Sendable {
    case single    // 单选
    case multiple  // 多选
}

/// 提问选项
struct ChatQuestionOption: Codable, Equatable, Identifiable, Sendable {
    let id: String   // 选项ID
    let text: String // 选项文本
}

/// 单个问题项
struct ToolQuestionItem: Identifiable, Equatable, Codable, Sendable {
    let id: String                  // 问题ID
    let question: String            // 问题文本
    let options: [ChatQuestionOption] // 选项列表
    let allowsOther: Bool           // 是否允许自定义输入
    let selectionMode: ChatQuestionSelectionMode // 选择模式
}

/// 成员选择提示
struct ToolMemberSelectionPrompt: Identifiable, Equatable, Codable, Sendable {
    let id: UUID              // 唯一标识
    let toolName: String      // 关联工具名
    let reason: String        // 选择原因
    let arguments: [String: String] // 工具参数
}

/// 工具提问提示
struct ToolQuestionPrompt: Identifiable, Equatable, Codable, Sendable {
    let id: UUID                  // 唯一标识
    let toolName: String          // 工具名
    let questions: [ToolQuestionItem] // 问题列表

    init(
        id: UUID = UUID(),
        toolName: String = SparkToolName.askUserQuestion.rawValue,
        questions: [ToolQuestionItem]
    ) {
        self.id = id
        self.toolName = toolName
        self.questions = questions
    }
}

/// 问题回答
struct ToolQuestionAnswer: Equatable, Codable, Sendable {
    let responses: [ToolQuestionResponse] // 回答列表
}

/// 单个问题的回答
struct ToolQuestionResponse: Equatable, Codable, Sendable {
    let questionID: String        // 问题ID
    let selectedOptionIDs: [String] // 选中的选项ID
    let otherText: String?        // 自定义输入文本
}

// MARK: - 工具模式匹配
/// 字符串与工具枚举匹配运算符重载（支持 switch case 直接使用枚举）
func ~=(pattern: SparkToolName, value: String) -> Bool {
    pattern.rawValue == value
}

// MARK: - 工具本地化与存储工具方法
extension SparkToolName {
    nonisolated static let noSelectionSentinel = "__spark_tools_none__" // 无选择标记

    /// 获取工具本地化显示名称
    nonisolated static func displayName(for toolName: String) -> String {
        L10n.text("ai_settings.tools.\(toolName)")
    }

    /// 从存储的工具名解析选中集合
    nonisolated static func selectedSet(fromStoredToolNames toolNames: [String]) -> Set<String> {
        if toolNames.contains(noSelectionSentinel) {
            return []
        }
        let normalized = Set(toolNames).intersection(Set(all))
        return normalized.isEmpty ? Set(all) : normalized
    }

    /// 转换为存储格式
    nonisolated static func storageValues(forSelectedToolNames selectedToolNames: Set<String>) -> [String] {
        let normalized = selectedToolNames.intersection(Set(all))
        return normalized.isEmpty ? [noSelectionSentinel] : normalized.sorted()
    }
}

// MARK: - 工具分组
/// 工具分组枚举（用于UI展示）
enum SparkToolGroup: String, CaseIterable {
    case health      // 健康
    case member      // 成员
    case location    // 位置
    case memory      // 记忆
    case knowledge   // 知识
    case system      // 系统

    /// 分组标题（本地化）
    var localizedTitle: String {
        L10n.text("ai_settings.tool_groups.\(rawValue)")
    }

    /// 分组描述（本地化）
    var localizedDescription: String {
        L10n.text("ai_settings.tool_groups.\(rawValue).description")
    }

    /// 分组图标（SF Symbol）
    var iconSystemName: String {
        switch self {
        case .health:
            return "heart.text.square"
        case .member:
            return "person.2"
        case .location:
            return "location"
        case .memory:
            return "brain.head.profile"
        case .knowledge:
            return "books.vertical"
        case .system:
            return "calendar.badge.clock"
        }
    }

    /// 当前分组包含的工具
    var tools: [SparkToolName] {
        switch self {
        case .health:
            return [
                .fetchStepDetails,
                .fetchEnergyDetails,
                .fetchNutritionDetails,
                .makeNutritionData,
                .fetchSleepDetails,
                .fetchWorkoutDetails,
                .generateStructuredHealthCard,
                .listMemberHealthSources,
                .getHealthResourceReference,
                .getHealthResourceContext
            ]
        case .member:
            return [
                .getCurrentMember,
                .requestMemberSelection,
                .switchMember,
                .findMember,
                .queryMemberProfile
            ]
        case .location:
            return [
                .queryLocation,
                .getCurrentLocation,
                .searchNearbyLocations,
                .getRoute,
                .queryWeather
            ]
        case .memory:
            return [
                .saveMemory,
                .retrieveMemory,
                .updateMemory,
                .generateChatTitle
            ]
        case .knowledge:
            return [
                .searchKnowledgeBag,
                .createKnowledgeDocument,
                .searchOnline,
                .readWebPage,
                .searchArxivPapers,
                .extractRemoteFileContent
            ]
        case .system:
            return [
                .searchCalendarAndReminders,
                .writeSystemEvent,
                .showCustomMessageCard,
                .showMedicalRiskNotice,
                .createCanvas,
                .editCanvas,
                .queryTasksByMember,
                .generateTask,
                .askUserQuestion
            ]
        }
    }

    /// 分组工具原始值数组
    var toolRawValues: [String] {
        tools.map(\.rawValue)
    }
}

// MARK: - 工具执行结果扩展（便捷方法）
extension ToolExecutionResult {
    /// 工具策略敏感度
    var toolPolicySensitivity: ToolDataSensitivity {
        SparkToolName(rawValue: toolName)?.declaredSensitivity ?? (sensitive ? .sensitive : .none)
    }

    /// 工具出口策略
    var toolEgressPolicy: ToolEgressPolicy {
        SparkToolName(rawValue: toolName)?.egressPolicy ?? (sensitive ? .requireConsent : .allow)
    }

    /// 是否需要模型授权
    var requiresModelConsent: Bool {
        switch toolEgressPolicy {
        case .allow:
            return sensitive
        case .requireConsent:
            return sensitive
        case .localOnly:
            return true
        }
    }

    /// 便捷初始化：直接传入枚举，无需写rawValue
    init(
        toolName: SparkToolName,
        outputText: String,
        sensitive: Bool,
        shouldBypassModel: Bool,
        isAwaitingUserInput: Bool = false,
        resolvedMemberID: Int? = nil,
        toolCallID: String? = nil,
        anchorToolCallID: String? = nil,
        arguments: [String: String]? = nil,
        sideEffects: [ToolSideEffect] = []
    ) {
        self.init(
            toolName: toolName.rawValue,
            outputText: outputText,
            sensitive: sensitive,
            shouldBypassModel: shouldBypassModel,
            isAwaitingUserInput: isAwaitingUserInput,
            resolvedMemberID: resolvedMemberID,
            toolCallID: toolCallID,
            anchorToolCallID: anchorToolCallID,
            arguments: arguments,
            sideEffects: sideEffects
        )
    }
}
