import Foundation

protocol AIRuntimeServing: Sendable {
    func generateTextStream(
        request: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error>
}

final class AIRuntimeService: AIRuntimeServing, @unchecked Sendable {
    private let configCenter: AIConfigCenter
    private let gateway: any AIRuntimeGateway
    private let localGateway: LocalGGUFTextGateway?
    private let logger: Logger

    init(
        configCenter: AIConfigCenter,
        gateway: any AIRuntimeGateway,
        localGateway: LocalGGUFTextGateway? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.configCenter = configCenter
        self.gateway = gateway
        self.localGateway = localGateway
        self.logger = logger
    }

    func generateTextStream(
        request: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error> {
        guard request.messages.isEmpty == false else {
            throw AIRuntimeError.emptyMessages
        }

        let start = Date()
        let resolved = try await configCenter.resolve(for: request.scenario)
        let snapshot = await configCenter.currentSnapshot()
        let supportsToolUse = modelSupportsTools(modelName: resolved.model, snapshot: snapshot)
        let providerFromCatalog = snapshot.allModels.first(where: { $0.name == resolved.model })?.company.uppercased()
        let effectiveRequest: AIRuntimeTextRequest = {
            guard supportsToolUse == false, request.tools.isEmpty == false else {
                return AIRuntimeTextRequest(
                    scenario: request.scenario,
                    messages: request.messages,
                    tools: request.tools,
                    toolChoice: request.toolChoice,
                    reasoning: request.reasoning,
                    providerCompanyUppercased: request.providerCompanyUppercased ?? providerFromCatalog
                )
            }
            logger.info(
                "当前模型不支持 tools，已按严格模式降级为纯文本回合，model=\(resolved.model)",
                category: "ai_runtime"
            )
            return AIRuntimeTextRequest(
                scenario: request.scenario,
                messages: request.messages,
                tools: [],
                toolChoice: .none,
                reasoning: request.reasoning,
                providerCompanyUppercased: request.providerCompanyUppercased ?? providerFromCatalog
            )
        }()

        if let localSelection = resolveLocalModelSelection(modelName: resolved.model, snapshot: snapshot) {
            guard let localGateway else {
                throw LocalModelServiceError.modelLoadFailed
            }
            var localMessages = effectiveRequest.messages
            if let prompt = localSelection.model.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
               prompt.isEmpty == false {
                localMessages.insert(AIRuntimeMessage(role: .system, content: prompt), at: 0)
            }
            logger.debug(
                "准备调用本地模型流式推理，scenario=\(request.scenario.rawValue), model=\(resolved.model), messages=\(localMessages.count), file=\(localSelection.fileName)",
                category: "ai_runtime"
            )
            let response = try await localGateway.generateText(
                fileName: localSelection.fileName,
                modelName: resolved.model,
                messages: localMessages,
                maxTokens: resolved.maxTokens,
                temperature: resolved.temperature
            )
            let cost = Date().timeIntervalSince(start)
            logger.info(
                "本地模型推理完成（流式封装），scenario=\(request.scenario.rawValue), model=\(response.model), cost=\(format(cost))s",
                category: "ai_runtime"
            )
            AIRuntimeOutputLog.recordFinalModelOutput(
                scenario: request.scenario,
                inferenceSource: resolved.source.rawValue,
                response: response,
                logger: logger
            )
            return AsyncThrowingStream { continuation in
                continuation.yield(.textDelta(response.text))
                continuation.yield(.completed(response))
                continuation.finish()
            }
        }

        let client = AIClientFactory.makeClient(from: resolved)
        logger.debug(
            "准备调用 AI 流式推理，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), model=\(resolved.model), messages=\(effectiveRequest.messages.count), tools=\(effectiveRequest.tools.count)",
            category: "ai_runtime"
        )
        let upstream = try await gateway.generateTextStream(client: client, request: effectiveRequest)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var finalResponse: AIRuntimeTextResponse?
                    for try await event in upstream {
                        if case .completed(let response) = event {
                            finalResponse = response
                        }
                        continuation.yield(event)
                    }
                    let cost = Date().timeIntervalSince(start)
                    if let finalResponse {
                        logger.info(
                            "AI 流式推理完成，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), model=\(finalResponse.model), cost=\(format(cost))s",
                            category: "ai_runtime"
                        )
                        AIRuntimeOutputLog.recordFinalModelOutput(
                            scenario: request.scenario,
                            inferenceSource: resolved.source.rawValue,
                            response: finalResponse,
                            logger: logger
                        )
                    } else {
                        logger.warning(
                            "AI 流式推理结束但缺少 completed 事件，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), cost=\(format(cost))s",
                            category: "ai_runtime"
                        )
                    }
                    continuation.finish()
                } catch {
                    let cost = Date().timeIntervalSince(start)
                    logger.error(
                        "AI 流式推理失败，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), model=\(resolved.model), cost=\(format(cost))s error=\(error.localizedDescription)",
                        category: "ai_runtime"
                    )
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func resolveLocalModelSelection(
        modelName: String,
        snapshot: AISettingsSnapshot
    ) -> (fileName: String, model: AllModels)? {
        guard let selected = snapshot.allModels.first(where: { $0.name == modelName }) else {
            return nil
        }

        guard selected.company.uppercased() == LocalModelService.localCompany else {
            return nil
        }

        if selected.identity == .model, let fileName = selected.localFilename, fileName.isEmpty == false {
            return (fileName, selected)
        }

        if selected.identity == .agent,
           let baseModelName = selected.baseModelName,
           let base = snapshot.allModels.first(where: { $0.name == baseModelName }),
           let fileName = base.localFilename,
           fileName.isEmpty == false {
            return (fileName, selected)
        }

        return nil
    }

    private func modelSupportsTools(modelName: String, snapshot: AISettingsSnapshot) -> Bool {
        guard let selected = snapshot.allModels.first(where: { $0.name == modelName }) else {
            return false
        }
        if selected.identity == .agent,
           let baseModelName = selected.baseModelName,
           let base = snapshot.allModels.first(where: { $0.name == baseModelName }) {
            return selected.supportsToolUse || base.supportsToolUse
        }
        return selected.supportsToolUse
    }

    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }
}
