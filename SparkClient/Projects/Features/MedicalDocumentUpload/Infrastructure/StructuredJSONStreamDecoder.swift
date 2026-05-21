import Foundation

struct StructuredJSONStreamResult<T: Decodable>: Sendable {
    let rawDelta: String
    let decoded: T?
    let isFinished: Bool
}

struct StructuredJSONStreamFinal<T: Decodable>: Sendable {
    let rawText: String
    let normalizedJSON: String
    let decoded: T?
}

struct StructuredJSONStreamDecoder<T: Decodable>: Sendable {
    let normalizer: MedicalDocumentModelJSONNormalizer
    let logger: Logger
    let kindLabel: String

    init(
        normalizer: MedicalDocumentModelJSONNormalizer = .init(),
        logger: Logger = ConsoleLogger(),
        kindLabel: String
    ) {
        self.normalizer = normalizer
        self.logger = logger
        self.kindLabel = kindLabel
    }

    func collect(
        from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> StructuredJSONStreamFinal<T> {
        var rawText = ""
        var latestDecoded: T?
        var fallbackFinalText = ""

        for try await event in stream {
            // 结构化 JSON 解析可能持续较久，逐帧检查取消可避免 UI 已返回但仍继续解析。
            try cancellationToken?.checkCancellation()
            switch event {
            case .textDelta(let delta):
                rawText.append(delta)
                latestDecoded = decodeCandidate(from: rawText) ?? latestDecoded
            case .completed(let response):
                fallbackFinalText = response.text
            case .reasoningDelta, .toolCallDelta:
                continue
            }
        }

        try cancellationToken?.checkCancellation()
        if rawText.isEmpty {
            rawText = fallbackFinalText
        }
        let normalized = normalizer.normalizedModelJSONText(rawText)
        let finalDecoded = decodeCandidate(from: normalized) ?? latestDecoded
        return .init(rawText: rawText, normalizedJSON: normalized, decoded: finalDecoded)
    }

    private func decodeCandidate(from text: String) -> T? {
        guard let candidate = normalizer.jsonCandidateString(from: text),
              let data = candidate.data(using: .utf8) else {
            return nil
        }
        do {
            return try JSONDecoder.default.decode(T.self, from: data)
        } catch {
            
            logger.error("流式结构化解码失败 error=\(error)", module: .medical)
            logger.error("流式结构化解码失败 kind=\(error.localizedDescription)", module: .medical)
            
            return nil
        }
    }
}
