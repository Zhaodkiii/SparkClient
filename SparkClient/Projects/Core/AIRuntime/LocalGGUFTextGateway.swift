import Foundation
import LLM

actor LocalModelRuntimePool {
    private var instances: [String: LLM] = [:]

    func model(
        for fileName: String,
        modelURL: URL,
        maxTokens: Int32,
        temperature: Float
    ) throws -> LLM {
        if let existing = instances[fileName] {
            existing.temp = temperature
            return existing
        }

        guard let model = LLM(from: modelURL, template: .chatML(), maxTokenCount: maxTokens) else {
            throw LocalModelServiceError.modelLoadFailed
        }
        model.temp = temperature
        instances[fileName] = model
        return model
    }
}

final class LocalGGUFTextGateway: @unchecked Sendable {
    private let localModelService: LocalModelService
    private let runtimePool = LocalModelRuntimePool()
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
        temperature: Double
    ) async throws -> AIRuntimeTextResponse {
        let modelURL = try await localModelService.localModelFileURL(fileName: fileName)
        let llm = try await runtimePool.model(
            for: fileName,
            modelURL: modelURL,
            maxTokens: Int32(max(maxTokens, 512)),
            temperature: Float(temperature)
        )

        let promptData = makePromptData(from: messages)
        llm.history = promptData.history
        if promptData.systemPrompt.isEmpty == false {
            llm.template = .chatML(promptData.systemPrompt)
        } else {
            llm.template = .chatML()
        }

        let prompt = llm.preprocess(promptData.input, promptData.history)
        let text = await llm.getCompletion(from: prompt)
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
