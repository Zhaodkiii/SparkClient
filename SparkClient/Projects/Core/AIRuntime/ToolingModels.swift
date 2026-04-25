import Foundation

enum ToolAuditStatus: String, Codable, Sendable {
    case success
    case denied
    case failed
}

struct ToolAuditEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let toolName: String
    let memberID: Int?
    let inputSummary: String
    let outputSummary: String
    let status: ToolAuditStatus
    let createdAt: Date

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

struct ToolExecutionResult: Sendable {
    let toolName: String
    let outputText: String
    let sensitive: Bool
    let shouldBypassModel: Bool
}

enum ToolHubResult: Sendable {
    case none
    case executed(ToolExecutionResult)
}

struct ToolInvocation: Sendable {
    let name: String
    let arguments: [String: String]
}

struct ToolExecutionContext: Sendable {
    let memberID: Int?
    let locale: Locale
    /// 当前助手消息 `clientMessageID`（异步医疗卡片回填目标）；仅模型工具轮次传入。
    let assistantMessageClientID: UUID?
    /// 当前会话 ID（与 ``assistantMessageClientID`` 成对使用）。
    let threadID: UUID?

    init(
        memberID: Int?,
        locale: Locale,
        assistantMessageClientID: UUID? = nil,
        threadID: UUID? = nil
    ) {
        self.memberID = memberID
        self.locale = locale
        self.assistantMessageClientID = assistantMessageClientID
        self.threadID = threadID
    }
}

struct ToolDefinition: Sendable {
    let name: String
    let summary: String
    let usage: String
}

enum SparkToolName: String, CaseIterable {
    case fetchStepDetails            = "fetch_step_details"
    case fetchEnergyDetails          = "fetch_energy_details"
    case fetchNutritionDetails       = "fetch_nutrition_details"
    case makeNutritionData           = "make_nutrition_data"
    case fetchSleepDetails           = "fetch_sleep_details"
    case fetchWorkoutDetails         = "fetch_workout_details"
    case searchKnowledgeBag          = "search_knowledge_bag"
    case createKnowledgeDocument     = "create_knowledge_document"
    case searchCalendarAndReminders  = "search_calendar_and_reminders"
    case writeSystemEvent            = "write_system_event"
    case queryLocation               = "query_location"
    case getCurrentLocation          = "get_current_location"
    case searchNearbyLocations       = "search_nearby_locations"
    case getRoute                    = "get_route"
    case queryWeather                = "query_weather"
    case saveMemory                  = "save_memory"
    case retrieveMemory              = "retrieve_memory"
    case updateMemory                = "update_memory"
    case generateChatTitle           = "generate_chat_title"
    case showCustomMessageCard       = "show_custom_message_card"
    case getCurrentMember            = "get_current_member"
    case switchMember                = "switch_member"
    case findMember                  = "find_member"
    case queryMemberProfile          = "query_member_profile"
    case searchOnline                = "search_online"
    case readWebPage                 = "read_web_page"
    case searchArxivPapers           = "search_arxiv_papers"
    case extractRemoteFileContent    = "extract_remote_file_content"
    case createCanvas                = "create_canvas"
    case editCanvas                  = "edit_canvas"
    case generateStructuredHealthCard = "generate_structured_health_card"
    case queryTasksByMember          = "query_tasks_by_member"
    case generateTask                = "generate_task"

    /// 自动派生，新增 case 后无需手动维护。
    static var all: [String] { allCases.map(\.rawValue) }
}

/// 允许在 `switch aString { case SparkToolName.xxx: }` 中使用枚举值做模式匹配，无需改动已有 switch。
func ~=(pattern: SparkToolName, value: String) -> Bool {
    pattern.rawValue == value
}

extension SparkToolName {
    static let noSelectionSentinel = "__spark_tools_none__"

    /// L10n key 规则统一为 `"ai_settings.tools.<tool_name>"`，直接插值即可，无需 switch。
    static func displayName(for toolName: String) -> String {
        L10n.text("ai_settings.tools.\(toolName)")
    }

    static func selectedSet(fromStoredToolNames toolNames: [String]) -> Set<String> {
        if toolNames.contains(noSelectionSentinel) {
            return []
        }
        let normalized = Set(toolNames).intersection(Set(all))
        return normalized.isEmpty ? Set(all) : normalized
    }

    static func storageValues(forSelectedToolNames selectedToolNames: Set<String>) -> [String] {
        let normalized = selectedToolNames.intersection(Set(all))
        return normalized.isEmpty ? [noSelectionSentinel] : normalized.sorted()
    }
}

enum SparkToolGroup: String, CaseIterable {
    case health
    case member
    case location
    case memory
    case knowledge
    case system

    var localizedTitle: String {
        L10n.text("ai_settings.tool_groups.\(rawValue)")
    }

    var localizedDescription: String {
        L10n.text("ai_settings.tool_groups.\(rawValue).description")
    }

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
                .generateStructuredHealthCard
            ]
        case .member:
            return [
                .getCurrentMember,
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
                .createCanvas,
                .editCanvas,
                .queryTasksByMember,
                .generateTask
            ]
        }
    }

    var toolRawValues: [String] {
        tools.map(\.rawValue)
    }
}

extension ToolExecutionResult {
    /// 接受 `SparkToolName` 枚举值，避免调用处写 `.rawValue`。
    init(toolName: SparkToolName, outputText: String, sensitive: Bool, shouldBypassModel: Bool) {
        self.init(toolName: toolName.rawValue, outputText: outputText, sensitive: sensitive, shouldBypassModel: shouldBypassModel)
    }
}
