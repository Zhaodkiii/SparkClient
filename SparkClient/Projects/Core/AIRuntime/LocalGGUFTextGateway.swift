import Foundation
import LLM

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
        let modelURL = try await localModelService.localModelFileURL(fileName: fileName)
        guard let llm = LLM(from: modelURL, template: .chatML(), maxTokenCount: Int32(max(maxTokens, 512))) else {
            throw LocalModelServiceError.modelLoadFailed
        }
        llm.temp = Float(temperature)

        let promptData = makePromptData(from: messages)
        llm.history = promptData.history
        if promptData.systemPrompt.isEmpty == false {
            llm.template = .chatML(promptData.systemPrompt)
        } else {
            llm.template = .chatML()
        }

        let prompt = llm.preprocess(promptData.input, promptData.history)
        let text = await llm.getCompletion(from: prompt)
        try cancellationToken?.checkCancellation()
        let output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.debug("本地模型推理完成：\(modelName)", module: .aiConfig)

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
        let modelURL = try await localModelService.localModelFileURL(fileName: fileName)

        return AsyncThrowingStream { continuation in
            let task = Task(priority: .userInitiated) {
                guard let llm = LLM(from: modelURL, template: .chatML(), maxTokenCount: Int32(max(maxTokens, 512))) else {
                    continuation.finish(throwing: LocalModelServiceError.modelLoadFailed)
                    return
                }
                llm.temp = Float(temperature)

                let promptData = makePromptData(from: messages)
                llm.history = promptData.history
                llm.template = promptData.systemPrompt.isEmpty ? .chatML() : .chatML(promptData.systemPrompt)

                var output = ""
                do {
                    try cancellationToken?.checkCancellation()

                    // LLM.swift 的 `respond` 可逐 token 回调；取消时必须调用 `llm.stop()` 释放本地推理循环。
                    await llm.respond(to: promptData.input) { responseStream in
                        for await delta in responseStream {
                            if cancellationToken?.isCancelled == true || Task.isCancelled {
                                llm.stop()
                                continuation.finish(throwing: CancellationError())
                                return output
                            }
                            output.append(delta)
                            continuation.yield(.textDelta(delta))
                        }
                        return output
                    }

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
                    logger.debug("本地模型流式推理完成：\(modelName)", module: .aiConfig)
                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch is CancellationError {
                    llm.stop()
                    logger.info("本地模型流式推理已中断：\(modelName)", module: .aiConfig)
                    continuation.finish(throwing: CancellationError())
                } catch {
                    llm.stop()
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { termination in
                self.logger.debug(
                    "本地 GGUF 流结束，termination=\(termination), model=\(modelName)",
                    module: .aiConfig
                )
                // 正常完成同样会触发 onTermination；只有真正取消时才停止底层 LLM。
                if case .cancelled = termination {
                    cancellationToken?.cancel()
                    task.cancel()
                }
            }
        }
    }

    private func makePromptData(from messages: [AIRuntimeMessage]) -> (systemPrompt: String, history: [Chat], input: String) {
        let systemMessages = messages.filter { $0.role == .system }.compactMap(\.content)
        let conversation = messages.filter { $0.role != .system }
        var input = ""
        if let lastUser = conversation.last(where: { $0.role == .user }) {
            input = lastUser.normalizedTextContent ?? ""
        } else if let last = conversation.last {
            input = last.normalizedTextContent ?? ""
        }

        let historyCandidates = conversation.dropLast()
        let history: [Chat] = historyCandidates.compactMap { message in
            switch message.role {
            case .user:
                return (.user, message.normalizedTextContent ?? "")
            case .assistant:
                return (.bot, message.normalizedTextContent ?? "")
            case .tool:
                return nil
            case .system:
                return nil
            }
        }

        return (
            systemPrompt: systemMessages.joined(separator: "\n\n"),
            history: history,
            input: input
        )
    }
}
