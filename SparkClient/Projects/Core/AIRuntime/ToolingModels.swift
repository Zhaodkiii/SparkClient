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

enum SparkToolName {
    static let fetchStepDetails = "fetch_step_details"
    static let fetchEnergyDetails = "fetch_energy_details"
    static let fetchNutritionDetails = "fetch_nutrition_details"
    static let makeNutritionData = "make_nutrition_data"
    static let fetchSleepDetails = "fetch_sleep_details"
    static let fetchWorkoutDetails = "fetch_workout_details"
    static let searchKnowledgeBag = "search_knowledge_bag"
    static let createKnowledgeDocument = "create_knowledge_document"
    static let searchCalendarAndReminders = "search_calendar_and_reminders"
    static let writeSystemEvent = "write_system_event"
    static let queryLocation = "query_location"
    static let getCurrentLocation = "get_current_location"
    static let searchNearbyLocations = "search_nearby_locations"
    static let getRoute = "get_route"
    static let queryWeather = "query_weather"
    static let saveMemory = "save_memory"
    static let retrieveMemory = "retrieve_memory"
    static let updateMemory = "update_memory"
    static let generateChatTitle = "generate_chat_title"
    static let showCustomMessageCard = "show_custom_message_card"
    static let getCurrentMember = "get_current_member"
    static let switchMember = "switch_member"
    static let findMember = "find_member"
    static let queryMemberProfile = "query_member_profile"
    static let searchOnline = "search_online"
    static let readWebPage = "read_web_page"
    static let searchArxivPapers = "search_arxiv_papers"
    static let extractRemoteFileContent = "extract_remote_file_content"
    static let createCanvas = "create_canvas"
    static let editCanvas = "edit_canvas"
    static let generateStructuredHealthCard = "generate_structured_health_card"
    static let queryTasksByMember = "query_tasks_by_member"
    static let generateTask = "generate_task"

    static let all: [String] = [
        fetchStepDetails,
        fetchEnergyDetails,
        fetchNutritionDetails,
        makeNutritionData,
        fetchSleepDetails,
        fetchWorkoutDetails,
        searchKnowledgeBag,
        createKnowledgeDocument,
        searchCalendarAndReminders,
        writeSystemEvent,
        queryLocation,
        getCurrentLocation,
        searchNearbyLocations,
        getRoute,
        queryWeather,
        saveMemory,
        retrieveMemory,
        updateMemory,
        generateChatTitle,
        showCustomMessageCard,
        getCurrentMember,
        switchMember,
        findMember,
        queryMemberProfile,
        searchOnline,
        readWebPage,
        searchArxivPapers,
        extractRemoteFileContent,
        createCanvas,
        editCanvas,
        generateStructuredHealthCard,
        queryTasksByMember,
        generateTask
    ]
}

extension SparkToolName {
    static func displayName(for toolName: String) -> String {
        switch toolName {
        case fetchStepDetails: return L10n.text("ai_settings.tools.fetch_step_details")
        case fetchEnergyDetails: return L10n.text("ai_settings.tools.fetch_energy_details")
        case fetchNutritionDetails: return L10n.text("ai_settings.tools.fetch_nutrition_details")
        case makeNutritionData: return L10n.text("ai_settings.tools.make_nutrition_data")
        case fetchSleepDetails: return L10n.text("ai_settings.tools.fetch_sleep_details")
        case fetchWorkoutDetails: return L10n.text("ai_settings.tools.fetch_workout_details")
        case searchKnowledgeBag: return L10n.text("ai_settings.tools.search_knowledge_bag")
        case createKnowledgeDocument: return L10n.text("ai_settings.tools.create_knowledge_document")
        case searchCalendarAndReminders: return L10n.text("ai_settings.tools.search_calendar_and_reminders")
        case writeSystemEvent: return L10n.text("ai_settings.tools.write_system_event")
        case queryLocation: return L10n.text("ai_settings.tools.query_location")
        case getCurrentLocation: return L10n.text("ai_settings.tools.get_current_location")
        case searchNearbyLocations: return L10n.text("ai_settings.tools.search_nearby_locations")
        case getRoute: return L10n.text("ai_settings.tools.get_route")
        case queryWeather: return L10n.text("ai_settings.tools.query_weather")
        case saveMemory: return L10n.text("ai_settings.tools.save_memory")
        case retrieveMemory: return L10n.text("ai_settings.tools.retrieve_memory")
        case updateMemory: return L10n.text("ai_settings.tools.update_memory")
        case generateChatTitle: return L10n.text("ai_settings.tools.generate_chat_title")
        case showCustomMessageCard: return L10n.text("ai_settings.tools.show_custom_message_card")
        case getCurrentMember: return L10n.text("ai_settings.tools.get_current_member")
        case switchMember: return L10n.text("ai_settings.tools.switch_member")
        case findMember: return L10n.text("ai_settings.tools.find_member")
        case queryMemberProfile: return L10n.text("ai_settings.tools.query_member_profile")
        case searchOnline: return L10n.text("ai_settings.tools.search_online")
        case readWebPage: return L10n.text("ai_settings.tools.read_web_page")
        case searchArxivPapers: return L10n.text("ai_settings.tools.search_arxiv_papers")
        case extractRemoteFileContent: return L10n.text("ai_settings.tools.extract_remote_file_content")
        case createCanvas: return L10n.text("ai_settings.tools.create_canvas")
        case editCanvas: return L10n.text("ai_settings.tools.edit_canvas")
        case generateStructuredHealthCard: return L10n.text("ai_settings.tools.generate_structured_health_card")
        case queryTasksByMember: return L10n.text("ai_settings.tools.query_tasks_by_member")
        case generateTask: return L10n.text("ai_settings.tools.generate_task")
        default: return toolName
        }
    }
}
