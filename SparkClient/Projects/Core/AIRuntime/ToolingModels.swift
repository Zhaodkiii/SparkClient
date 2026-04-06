import Foundation

enum ToolAuditStatus: String, Codable, Sendable {
    case success
    case denied
    case failed
}

struct ToolAuditEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let toolName: String
    let patientID: Int?
    let inputSummary: String
    let outputSummary: String
    let status: ToolAuditStatus
    let createdAt: Date

    init(
        id: UUID = UUID(),
        toolName: String,
        patientID: Int?,
        inputSummary: String,
        outputSummary: String,
        status: ToolAuditStatus,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.patientID = patientID
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
    let patientID: Int?
    let locale: Locale
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
    static let ocrExtractDraft = "ocr_extract_draft"
    static let confirmDraft = "confirm_draft"

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
        ocrExtractDraft,
        confirmDraft
    ]
}
