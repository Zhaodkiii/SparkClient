import Foundation

final class LocalGGUFTextGateway: @unchecked Sendable {
    private let localModelService: LocalModelService
    private let logger: Logger

    init(
        localModelService: LocalModelService,
        logger: Logger = ConsoleLogger()
    ) {
        self.localModelService = localModelService
        self.logger = logger
    }

    func generateText(
        fileName: String,
        modelName: String,
        messages: [AIRuntimeMessage],
        maxTokens: Int,
        temperature: Double,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> AIRuntimeTextResponse {
        try cancellationToken?.checkCancellation()
        _ = fileName
        _ = maxTokens
        _ = temperature

        let text = makePlaceholderText(from: messages)
        try cancellationToken?.checkCancellation()
        let output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("本地 GGUF 能力已临时禁用，返回占位结果：\(modelName)", module: .aiConfig)

        return AIRuntimeTextResponse(
            text: output,
            reasoningText: nil,
            model: modelName,
            promptTokens: nil,
            completionTokens: nil,
            toolCalls: [],
            finishReason: "stop"
        )
    }

    func generateTextStream(
        fileName: String,
        modelName: String,
        messages: [AIRuntimeMessage],
        maxTokens: Int,
        temperature: Double,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error> {
        try cancellationToken?.checkCancellation()
        _ = fileName
        _ = maxTokens
        _ = temperature

        return AsyncThrowingStream { continuation in
            let task = Task(priority: .userInitiated) {
                do {
                    try cancellationToken?.checkCancellation()
                    let output = makePlaceholderText(from: messages)
                    if cancellationToken?.isCancelled == true || Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    continuation.yield(.textDelta(output))

                    try cancellationToken?.checkCancellation()
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let response = AIRuntimeTextResponse(
                        text: trimmed,
                        reasoningText: nil,
                        model: modelName,
                        promptTokens: nil,
                        completionTokens: nil,
                        toolCalls: [],
                        finishReason: "stop"
                    )
                    logger.info("本地 GGUF 流式能力已临时禁用，返回占位结果：\(modelName)", module: .aiConfig)
                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch is CancellationError {
                    logger.info("本地模型流式推理已中断：\(modelName)", module: .aiConfig)
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { termination in
                self.logger.debug(
                    "本地 GGUF 流结束，termination=\(termination), model=\(modelName)",
                    module: .aiConfig
                )
                if case .cancelled = termination {
                    cancellationToken?.cancel()
                    task.cancel()
                }
            }
        }
    }

    private func makePlaceholderText(from messages: [AIRuntimeMessage]) -> String {
        let conversation = messages.filter { $0.role != .system }
        let input = conversation.last(where: { $0.role == .user })?.normalizedTextContent
            ?? conversation.last?.normalizedTextContent
            ?? ""

        if input.isEmpty {
            return "Local GGUF is temporarily disabled."
        }

        return input
    }
}
