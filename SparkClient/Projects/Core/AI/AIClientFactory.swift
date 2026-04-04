import Foundation

/// 第一阶段使用轻量客户端描述符，后续再接入真实模型 SDK。
struct AIClient: Equatable, Sendable {
    let endpoint: URL
    let model: String
    let apiKey: String?
    let temperature: Double
    let maxTokens: Int
}

enum AIClientFactory {
    static func makeClient(from config: AIResolvedConfig) -> AIClient {
        AIClient(
            endpoint: config.endpoint,
            model: config.model,
            apiKey: config.apiKey,
            temperature: config.temperature,
            maxTokens: config.maxTokens
        )
    }
}
