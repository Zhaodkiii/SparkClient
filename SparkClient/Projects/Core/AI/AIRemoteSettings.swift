import Foundation

protocol AIRemoteConfigProvider: Sendable {
    func fetchRemotePatch() async throws -> AIRemoteSettingsPatch
}

struct AIRemoteSettingsPatch: Equatable, Sendable {
    var revision: String?
    var chat: AIScenarioConfig?
    var medicalExtraction: AIScenarioConfig?
    var embedding: AIScenarioConfig?
    var apiKeys: [APIKeys]?
    var searchKeys: [SearchKeys]?
    var toolKeys: [ToolKeys]?
    var allModels: [AllModels]?
    var userInfo: AIRemoteUserInfoPatch?

    init(
        revision: String? = nil,
        chat: AIScenarioConfig? = nil,
        medicalExtraction: AIScenarioConfig? = nil,
        embedding: AIScenarioConfig? = nil,
        apiKeys: [APIKeys]? = nil,
        searchKeys: [SearchKeys]? = nil,
        toolKeys: [ToolKeys]? = nil,
        allModels: [AllModels]? = nil,
        userInfo: AIRemoteUserInfoPatch? = nil
    ) {
        self.revision = revision
        self.chat = chat
        self.medicalExtraction = medicalExtraction
        self.embedding = embedding
        self.apiKeys = apiKeys
        self.searchKeys = searchKeys
        self.toolKeys = toolKeys
        self.allModels = allModels
        self.userInfo = userInfo
    }
}

struct AIRemoteUserInfoPatch: Equatable, Sendable {
    var chooseEmbeddingModel: String?
    var optimizationTextModel: String?
    var optimizationVisualModel: String?
    var textToSpeechModel: String?
    var useKnowledge: Bool?
    var knowledgeCount: Int?
    var knowledgeSimilarity: Double?
    var useSearch: Bool?
    var bilingualSearch: Bool?
    var searchCount: Int?
    var useMap: Bool?
    var useCalendar: Bool?
    var useWeather: Bool?
    var useCanvas: Bool?
    var useCode: Bool?

    init(
        chooseEmbeddingModel: String? = nil,
        optimizationTextModel: String? = nil,
        optimizationVisualModel: String? = nil,
        textToSpeechModel: String? = nil,
        useKnowledge: Bool? = nil,
        knowledgeCount: Int? = nil,
        knowledgeSimilarity: Double? = nil,
        useSearch: Bool? = nil,
        bilingualSearch: Bool? = nil,
        searchCount: Int? = nil,
        useMap: Bool? = nil,
        useCalendar: Bool? = nil,
        useWeather: Bool? = nil,
        useCanvas: Bool? = nil,
        useCode: Bool? = nil
    ) {
        self.chooseEmbeddingModel = chooseEmbeddingModel
        self.optimizationTextModel = optimizationTextModel
        self.optimizationVisualModel = optimizationVisualModel
        self.textToSpeechModel = textToSpeechModel
        self.useKnowledge = useKnowledge
        self.knowledgeCount = knowledgeCount
        self.knowledgeSimilarity = knowledgeSimilarity
        self.useSearch = useSearch
        self.bilingualSearch = bilingualSearch
        self.searchCount = searchCount
        self.useMap = useMap
        self.useCalendar = useCalendar
        self.useWeather = useWeather
        self.useCanvas = useCanvas
        self.useCode = useCode
    }
}
