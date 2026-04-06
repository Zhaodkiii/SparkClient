import Foundation

/// 从 `AISettingsSnapshot` 解析嵌入调用所需的模型名、密钥与 `/embeddings` 端点。
enum KnowledgeEmbeddingResolution {
    struct Resolved: Sendable {
        /// 发往 API 的 `model` 字段（可能经厂商别名映射）。
        let apiModelName: String
        let apiKey: String
        let embeddingsURL: URL
    }

    /// 与 UI 一致的「可见嵌入模型」：名称像嵌入模型且对应厂商已配置非空密钥。
    static func visibleEmbeddingModels(in snapshot: AISettingsSnapshot) -> [AllModels] {
        snapshot.allModels.filter { model in
            guard isEmbeddingCandidateName(model.name) else { return false }
            return apiKeyEntry(for: model.company, in: snapshot) != nil
        }
        .sorted { $0.position < $1.position }
    }

    static func resolve(modelName: String, snapshot: AISettingsSnapshot) throws -> Resolved {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ResolutionError.emptyModelName
        }
        guard let model = snapshot.allModels.first(where: { $0.name == trimmed }) else {
            throw ResolutionError.modelNotFound(trimmed)
        }
        guard let keyEntry = apiKeyEntry(for: model.company, in: snapshot) else {
            throw ResolutionError.missingAPIKey(model.company)
        }

        let apiModel = mapProviderModelName(model.name)
        let url = resolveEmbeddingURL(providerEndpoint: keyEntry.requestURL, modelName: apiModel)
        guard let embeddingsURL = URL(string: url) else {
            throw ResolutionError.invalidURL(url)
        }

        return Resolved(apiModelName: apiModel, apiKey: keyEntry.key, embeddingsURL: embeddingsURL)
    }

    private static func apiKeyEntry(for company: String, in snapshot: AISettingsSnapshot) -> APIKeys? {
        let upper = company.uppercased()
        let candidates = snapshot.apiKeys.filter { $0.company.uppercased() == upper }
        let nonEmpty = candidates.filter { $0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        if let preferred = nonEmpty.first(where: { $0.requestURL.lowercased().contains("embedding") }) {
            return preferred
        }
        return nonEmpty.first
    }

    private static func isEmbeddingCandidateName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("embedding") { return true }
        if lower.hasPrefix("text-embedding") { return true }
        if lower.contains("bge") && lower.contains("m3") { return true }
        return false
    }

    /// 与 Health `KnowledgeAPI.generateEmbeddings` 一致的别名。
    private static func mapProviderModelName(_ name: String) -> String {
        if name == "Hanlin-BAAI/bge-m3" {
            return "BAAI/bge-m3"
        }
        return name
    }

    /// 将聊天基址转为 OpenAI 兼容的 `.../embeddings`（对齐 Health `resolveEmbeddingURL`）。
    private static func resolveEmbeddingURL(providerEndpoint: String, modelName: String) -> String {
        let endpoint = providerEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint.contains("/chat/completions") {
            if modelName.lowercased().contains("vision") {
                return endpoint.replacingOccurrences(of: "/chat/completions", with: "/embeddings/multimodal")
            }
            return endpoint.replacingOccurrences(of: "/chat/completions", with: "/embeddings")
        }
        if endpoint.contains("/responses") {
            return endpoint.replacingOccurrences(of: "/responses", with: "/embeddings")
        }
        if endpoint.hasSuffix("/") {
            return endpoint + "embeddings"
        }
        if endpoint.lowercased().hasSuffix("/embeddings") || endpoint.contains("/embeddings") {
            return endpoint
        }
        return endpoint + "/embeddings"
    }

    enum ResolutionError: LocalizedError {
        case emptyModelName
        case modelNotFound(String)
        case missingAPIKey(String)
        case invalidURL(String)

        var errorDescription: String? {
            switch self {
            case .emptyModelName:
                return "未选择嵌入模型。"
            case .modelNotFound(let name):
                return "未找到嵌入模型：\(name)"
            case .missingAPIKey(let company):
                return "未配置 \(company) 的 API Key。"
            case .invalidURL(let url):
                return "无效的嵌入端点：\(url)"
            }
        }
    }
}
