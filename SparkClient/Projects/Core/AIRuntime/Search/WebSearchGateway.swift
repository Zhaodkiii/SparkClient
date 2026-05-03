import Foundation

protocol WebSearchProvider: Sendable {
    var provider: SearchProviderID { get }
    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse
}

final class WebSearchGateway: @unchecked Sendable {
    private let providers: [SearchProviderID: any WebSearchProvider]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        let list: [any WebSearchProvider] = [
            TavilySearchProvider(session: session),
            SerpAPISearchProvider(session: session),
            ZhipuSearchProvider(session: session),
            BraveSearchProvider(session: session),
            ExaSearchProvider(session: session),
            BochaSearchProvider(session: session),
            LangSearchProvider(session: session),
            PerplexitySearchProvider(session: session)
        ]
        providers = Dictionary(uniqueKeysWithValues: list.map { ($0.provider, $0) })
    }

    func search(query: String, config: SearchRuntimeConfig) async throws -> WebSearchResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw SearchRuntimeError.emptyQuery }
        guard let provider = providers[config.provider] else {
            throw SearchRuntimeError.unsupportedProvider(config.displayName)
        }
        return try await provider.search(WebSearchRequest(query: trimmed, config: config))
    }

    func readWebPage(urlString: String) async throws -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            throw SearchRuntimeError.invalidEndpoint(trimmed)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let text = Self.extractReadableText(from: html)
        let clipped = String(text.prefix(12000))
        return clipped.isEmpty ? "网页读取完成，但未提取到可读正文。" : clipped
    }

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw SearchRuntimeError.badHTTPStatus(http.statusCode, body)
        }
    }

    static func jsonRequest(url: URL, apiKey: String, body: [String: Any], authorization: String? = nil) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        } else if apiKey.isEmpty == false {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func extractReadableText(from html: String) -> String {
        var text = html
        let patterns = [
            "(?is)<script[^>]*>.*?</script>",
            "(?is)<style[^>]*>.*?</style>",
            "(?is)<[^>]+>"
        ]
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'"
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}
