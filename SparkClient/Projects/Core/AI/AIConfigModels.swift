import Foundation

enum AIConfigSource: String, Codable, Sendable {
    case localDefault
    case runtimeOverride
}

struct AIScenarioConfig: Codable, Equatable, Sendable {
    var endpoint: String
    var model: String
    var apiKey: String?
    var temperature: Double
    var maxTokens: Int

    init(
        endpoint: String,
        model: String,
        apiKey: String? = nil,
        temperature: Double = 0.2,
        maxTokens: Int = 2048
    ) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    func toResolvedConfig(source: AIConfigSource) throws -> AIResolvedConfig {
        guard let url = URL(string: endpoint), url.scheme != nil else {
            throw AIConfigError.invalidEndpoint(endpoint)
        }
        return AIResolvedConfig(
            endpoint: url,
            model: model,
            apiKey: apiKey,
            temperature: temperature,
            maxTokens: maxTokens,
            source: source
        )
    }
}

struct AIResolvedConfig: Equatable, Sendable {
    let endpoint: URL
    let model: String
    let apiKey: String?
    let temperature: Double
    let maxTokens: Int
    let source: AIConfigSource
}

enum AIConfigError: LocalizedError {
    case invalidEndpoint(String)
    case missingScenario(AIScenario)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let endpoint):
            return "Invalid AI endpoint: \(endpoint)"
        case .missingScenario(let scenario):
            return "Missing AI config for scenario: \(scenario.rawValue)"
        }
    }
}
