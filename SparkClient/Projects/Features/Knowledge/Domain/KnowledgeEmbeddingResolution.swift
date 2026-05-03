import Foundation

/// 从运行时合并后的 embedding 场景 bundle 解析嵌入调用所需的模型名、密钥与端点。
enum KnowledgeEmbeddingResolution {
    struct Resolved: Sendable {
        /// 发往 API 的 `model` 字段（可能经厂商别名映射）。
        let apiModelName: String
        let apiKey: String
        let embeddingsURL: URL
    }

    static func resolve(modelName: String?, in bundles: AIScenarioRemoteBundlesCollection) throws -> Resolved {
        guard let row = bundles.resolveRow(for: .embedding, preferredModelName: modelName?.trimmedNilIfEmpty) else {
            throw AIConfigError.missingModelForScenario(.embedding)
        }
        return try resolve(row: row)
    }

    static func resolve(row: AIScenarioRemoteModelRow) throws -> Resolved {
        let apiModel = (row.baseModelName?.trimmedNilIfEmpty ?? row.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard apiModel.isEmpty == false else {
            throw ResolutionError.emptyModelName
        }
        let endpoint = resolveEmbeddingURL(providerEndpoint: row.endpoint, modelName: apiModel)
        guard let embeddingsURL = URL(string: endpoint), embeddingsURL.scheme != nil else {
            throw ResolutionError.invalidURL(endpoint)
        }
        return Resolved(
            apiModelName: apiModel,
            apiKey: row.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            embeddingsURL: embeddingsURL
        )
    }

    /// 本地 bundle 可能仍复用厂商的 chat/responses 基址，运行时调用前统一落到 embeddings 端点。
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
        case invalidURL(String)

        var errorDescription: String? {
            switch self {
            case .emptyModelName:
                return "未选择嵌入模型。"
            case .invalidURL(let url):
                return "无效的嵌入端点：\(url)"
            }
        }
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
