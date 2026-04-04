import Foundation

/// 传输层原始结果：响应体字节与 `HTTPURLResponse`（不做 JSON 解码）。
struct SparkTransportResponse: Sendable {
    let data: Data
    let httpResponse: HTTPURLResponse
}

/// 最底层 HTTP 发送抽象，便于单测注入 mock。
protocol SparkNetworkTransport: Sendable {
    func send(_ urlRequest: URLRequest) async throws -> SparkTransportResponse
}

/// 基于 `URLSession` 的默认实现：只返回字节与状态码，不解析业务 JSON。
struct URLSessionNetworkTransport: SparkNetworkTransport {
    let session: URLSession
    let logger: Logger

    /// 默认使用 `URLSession.shared` 与控制台日志。
    init(session: URLSession = .shared, logger: Logger = ConsoleLogger()) {
        self.session = session
        self.logger = logger
    }

    func send(_ urlRequest: URLRequest) async throws -> SparkTransportResponse {
        let request = urlRequest
        let method = request.httpMethod ?? "GET"
        let path = request.url?.absoluteString ?? "-"
        let requestId = request.value(forHTTPHeaderField: "X-Request-ID") ?? "-"
        // 出站摘要：脱敏头 + UTF-8 可打印 body（见 NetworkLogSanitizer）。
        let requestHeaders = NetworkLogSanitizer.headersPreview(request.allHTTPHeaderFields)
        let requestBody = NetworkLogSanitizer.bodyPreview(data: request.httpBody, contentType: request.value(forHTTPHeaderField: "Content-Type"))

        logger.debug(SparkNetworkingStrings.HTTPClient.startingRequest(method: method, path: path))
        logger.info(
            SparkNetworkingStrings.HTTPClient.outbound(
                method: method,
                path: path,
                requestId: requestId,
                headers: requestHeaders,
                body: requestBody
            ),
            category: "network.io"
        )
        do {
            let start = Date()
            let (data, response) = try await session.data(for: request, delegate: nil)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SparkNetworkError.invalidResponse
            }
            // 往返耗时，写入入站日志。
            let cost = Date().timeIntervalSince(start)
            let responseBody = NetworkLogSanitizer.bodyPreview(
                data: data,
                contentType: httpResponse.value(forHTTPHeaderField: "Content-Type")
            )
            let responseHeaders = NetworkLogSanitizer.headersPreview(httpResponse.allHeaderFields)
            logger.info(
                SparkNetworkingStrings.HTTPClient.completedRequest(
                    method: method,
                    path: path,
                    statusCode: httpResponse.statusCode
                )
            )
            logger.info(
                SparkNetworkingStrings.HTTPClient.inbound(
                method: method,
                path: path,
                requestId: requestId,
                statusCode: httpResponse.statusCode,
                cost: cost,
                headers: responseHeaders,
                body: responseBody
            ),
                category: "network.io"
            )
            return SparkTransportResponse(data: data, httpResponse: httpResponse)
        } catch let urlError as URLError {
            // 映射为 `SparkNetworkError.transport`，由引擎统一重试策略处理。
            logger.warning(
                SparkNetworkingStrings.HTTPClient.failedRequest(
                    method: method,
                    path: path,
                    reason: "URLError(\(urlError.code.rawValue))"
                )
            )
            throw SparkNetworkError.transport(urlError)
        } catch {
            // 非 URLError（如解码、编程错误）：记录后原样上抛。
            logger.error(
                SparkNetworkingStrings.HTTPClient.failedRequest(
                    method: method,
                    path: path,
                    reason: error.localizedDescription
                )
            )
            throw error
        }
    }
}

/// 网络日志里的头与 body 预览：脱敏、转义，避免泄露 token。
private enum NetworkLogSanitizer {
    /// `URLRequest` / `HTTPURLResponse` 的 `allHeaderFields`（键类型为 `AnyHashable`）。
    static func headersPreview(_ headers: [AnyHashable: Any]?) -> String {
        guard let headers, headers.isEmpty == false else { return "{}" }
        let normalized = Dictionary(uniqueKeysWithValues: headers.map { (String(describing: $0.key), String(describing: $0.value)) })
        return serializeDictionary(normalized)
    }

    /// 已是 `[String: String]` 的头字典（较少用）。
    static func headersPreview(_ headers: [String: String]?) -> String {
        guard let headers, headers.isEmpty == false else { return "{}" }
        return serializeDictionary(headers)
    }

    /// 将 body 转为日志字符串；非 UTF-8 文本显示字节长度占位。
    static func bodyPreview(data: Data?, contentType: String?) -> String {
        guard let data, data.isEmpty == false else { return "" }

        guard let text = String(data: data, encoding: .utf8) else {
            return "<二进制：\(data.count) 字节>"
        }

        // 预留 `contentType` 参数，便于日后按类型截断或脱敏。
        _ = contentType
        return text
    }

    /// 排序键名后拼成单行 JSON 风格字符串，并对 `Authorization` 脱敏。
    private static func serializeDictionary(_ source: [String: String]) -> String {
        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(source.count)

        for (key, value) in source {
            if key.caseInsensitiveCompare("Authorization") == .orderedSame {
                sanitized[key] = redactAuthorization(value)
            } else {
                sanitized[key] = value
            }
        }

        // 稳定顺序，便于 diff 日志。
        let ordered = sanitized.keys.sorted().map { key in
            "\"\(key)\":\"\(escape(sanitized[key] ?? ""))\""
        }
        return "{\(ordered.joined(separator: ","))}"
    }

    /// `Bearer <token>` 等形式：保留 scheme，凭证替换为 `***`。
    private static func redactAuthorization(_ value: String) -> String {
        guard value.isEmpty == false else { return value }
        let comps = value.split(separator: " ", maxSplits: 1).map(String.init)
        guard comps.count == 2 else { return "***" }
        return "\(comps[0]) ***"
    }

    /// 嵌入 JSON 字面量时转义 `\`、`"`、换行。
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
