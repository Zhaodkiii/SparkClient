import Foundation

protocol AIRemoteConfigProvider: Sendable {
    func fetchRemotePatch() async throws -> AIRemoteSettingsPatch
}

struct AIRemoteSettingsPatch: Equatable, Sendable {
    var revision: String?
    /// When set, merged first; flat scenario fields below remain for backward-compatible merges.
    var scenarioRemoteBundles: AIScenarioRemoteBundlesCollection?
    var chat: AIScenarioConfig?
    var optimizationText: AIScenarioConfig?
    var optimizationVisual: AIScenarioConfig?
    var contextFolding: AIScenarioConfig?
    var router: AIScenarioConfig?
    var modelConfig: AIScenarioConfig?
    var reportInterpretation: AIScenarioConfig?
    var apiKeys: [APIKeys]?
    var searchKeys: [SearchKeys]?
    var toolKeys: [ToolKeys]?
    var allModels: [AllModels]?
    var userInfo: AIRemoteUserInfoPatch?
    var trial: AITrialState?
    var trialModelPolicy: [AITrialModelPolicyItem]?

    init(
        revision: String? = nil,
        scenarioRemoteBundles: AIScenarioRemoteBundlesCollection? = nil,
        chat: AIScenarioConfig? = nil,
        optimizationText: AIScenarioConfig? = nil,
        optimizationVisual: AIScenarioConfig? = nil,
        contextFolding: AIScenarioConfig? = nil,
        router: AIScenarioConfig? = nil,
        modelConfig: AIScenarioConfig? = nil,
        reportInterpretation: AIScenarioConfig? = nil,
        apiKeys: [APIKeys]? = nil,
        searchKeys: [SearchKeys]? = nil,
        toolKeys: [ToolKeys]? = nil,
        allModels: [AllModels]? = nil,
        userInfo: AIRemoteUserInfoPatch? = nil,
        trial: AITrialState? = nil,
        trialModelPolicy: [AITrialModelPolicyItem]? = nil
    ) {
        self.revision = revision
        self.scenarioRemoteBundles = scenarioRemoteBundles
        self.chat = chat
        self.optimizationText = optimizationText
        self.optimizationVisual = optimizationVisual
        self.contextFolding = contextFolding
        self.router = router
        self.modelConfig = modelConfig
        self.reportInterpretation = reportInterpretation
        self.apiKeys = apiKeys
        self.searchKeys = searchKeys
        self.toolKeys = toolKeys
        self.allModels = allModels
        self.userInfo = userInfo
        self.trial = trial
        self.trialModelPolicy = trialModelPolicy
    }
}

struct AIRemoteUserInfoPatch: Equatable, Sendable {
    var chooseEmbeddingModel: String?
    var optimizationTextModel: String?
    var optimizationVisualModel: String?
    var contextFoldingModel: String?
    var routerModel: String?
    var dataExtractionModel: String?
    var reportInterpretationModel: String?
    var textToSpeechModel: String?
    var useContextFolding: Bool?
    var maxToolSets: Int?
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
        contextFoldingModel: String? = nil,
        routerModel: String? = nil,
        dataExtractionModel: String? = nil,
        reportInterpretationModel: String? = nil,
        textToSpeechModel: String? = nil,
        useContextFolding: Bool? = nil,
        maxToolSets: Int? = nil,
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
        self.contextFoldingModel = contextFoldingModel
        self.routerModel = routerModel
        self.dataExtractionModel = dataExtractionModel
        self.reportInterpretationModel = reportInterpretationModel
        self.textToSpeechModel = textToSpeechModel
        self.useContextFolding = useContextFolding
        self.maxToolSets = maxToolSets
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
