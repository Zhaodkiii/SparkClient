import Foundation

/// OpenAI 兼容 `POST .../embeddings` 客户端。
protocol KnowledgeEmbeddingClient: Sendable {
    func embed(texts: [String], modelName: String, apiKey: String, endpointURL: URL) async throws -> [[Float]]
}

final class OpenAICompatibleEmbeddingClient: KnowledgeEmbeddingClient {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func embed(texts: [String], modelName: String, apiKey: String, endpointURL: URL) async throws -> [[Float]] {
        guard texts.isEmpty == false else { return [] }

        let isVolcMultimodal = endpointURL.absoluteString.contains("/embeddings/multimodal")
        if isVolcMultimodal {
            var out: [[Float]] = []
            out.reserveCapacity(texts.count)
            for text in texts {
                let body: [String: Any] = [
                    "model": modelName,
                    "input": [
                        ["type": "text", "text": text]
                    ]
                ]
                let vec = try await requestSingleEmbedding(url: endpointURL, apiKey: apiKey, body: body)
                out.append(vec)
            }
            return out
        }

        var body: [String: Any] = [
            "model": modelName,
            "input": texts,
            "encoding_format": "float"
        ]
        if modelName != "BAAI/bge-m3" {
            body["dimensions"] = 1024
        }
        return try await requestBatchEmbeddings(url: endpointURL, apiKey: apiKey, body: body, expectedCount: texts.count)
    }

    private func requestBatchEmbeddings(
        url: URL,
        apiKey: String,
        body: [String: Any],
        expectedCount: Int
    ) async throws -> [[Float]] {
        let (data, response) = try await postJSON(url: url, apiKey: apiKey, body: body)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8) ?? ""
            throw EmbeddingHTTPError.status(code, message)
        }
        let parsed = try parseEmbeddingDataArray(from: data)
        guard parsed.count == expectedCount else {
            throw EmbeddingHTTPError.countMismatch(expected: expectedCount, actual: parsed.count)
        }
        return parsed
    }

    private func requestSingleEmbedding(url: URL, apiKey: String, body: [String: Any]) async throws -> [Float] {
        let (data, response) = try await postJSON(url: url, apiKey: apiKey, body: body)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8) ?? ""
            throw EmbeddingHTTPError.status(code, message)
        }
        let parsed = try parseEmbeddingDataArray(from: data)
        guard let first = parsed.first else {
            throw EmbeddingHTTPError.emptyPayload
        }
        return first
    }

    private func postJSON(url: URL, apiKey: String, body: [String: Any]) async throws -> (Data, URLResponse) {
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty == false {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }
        return try await urlSession.data(for: request)
    }

    private func parseEmbeddingDataArray(from data: Data) throws -> [[Float]] {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EmbeddingHTTPError.parseFailed
        }
        let dataField = jsonObject["data"]
        if let dataArray = dataField as? [[String: Any]] {
            return try dataArray.enumerated().map { idx, dict in
                try parseEmbeddingRow(dict: dict, idx: idx)
            }
        }
        if let dataObject = dataField as? [String: Any] {
            let vec = try parseEmbeddingRow(dict: dataObject, idx: 0)
            return [vec]
        }
        throw EmbeddingHTTPError.parseFailed
    }

    private func parseEmbeddingRow(dict: [String: Any], idx: Int) throws -> [Float] {
        if let values = dict["embedding"] as? [Double], !values.isEmpty {
            return values.map { Float($0) }
        }
        if let values = dict["embedding"] as? [Float], !values.isEmpty {
            return values
        }
        if let values = dict["embedding"] as? [NSNumber], !values.isEmpty {
            return values.map { $0.floatValue }
        }
        if let embeddingObject = dict["embedding"] as? [String: Any] {
            if let values = embeddingObject["text_embedding"] as? [NSNumber], !values.isEmpty {
                return values.map { $0.floatValue }
            }
            if let values = embeddingObject["vector"] as? [NSNumber], !values.isEmpty {
                return values.map { $0.floatValue }
            }
        }
        throw EmbeddingHTTPError.parseFailedRow(idx)
    }

    enum EmbeddingHTTPError: LocalizedError {
        case status(Int, String)
        case countMismatch(expected: Int, actual: Int)
        case emptyPayload
        case parseFailed
        case parseFailedRow(Int)

        var errorDescription: String? {
            switch self {
            case .status(let code, let message):
                return "嵌入请求失败（\(code)）：\(message.prefix(400))"
            case .countMismatch(let expected, let actual):
                return "嵌入数量不一致：期望 \(expected)，实际 \(actual)。"
            case .emptyPayload:
                return "嵌入响应为空。"
            case .parseFailed:
                return "无法解析嵌入响应。"
            case .parseFailedRow(let idx):
                return "无法解析嵌入行 \(idx)。"
            }
        }
    }
}
