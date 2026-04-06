import Foundation

protocol AIRuntimeServing: Sendable {
    func generateText(request: AIRuntimeTextRequest) async throws -> AIRuntimeTextResponse
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

    func generateText(request: AIRuntimeTextRequest) async throws -> AIRuntimeTextResponse {
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
                "准备调用本地模型推理，scenario=\(request.scenario.rawValue), model=\(resolved.model), messages=\(localMessages.count), file=\(localSelection.fileName)",
                category: "ai_runtime"
            )
            do {
                let response = try await localGateway.generateText(
                    fileName: localSelection.fileName,
                    modelName: resolved.model,
                    messages: localMessages,
                    maxTokens: resolved.maxTokens,
                    temperature: resolved.temperature
                )
                let cost = Date().timeIntervalSince(start)
                logger.info(
                    "本地模型推理完成，scenario=\(request.scenario.rawValue), model=\(response.model), cost=\(format(cost))s",
                    category: "ai_runtime"
                )
                return response
            } catch {
                let cost = Date().timeIntervalSince(start)
                logger.error(
                    "本地模型推理失败，scenario=\(request.scenario.rawValue), model=\(resolved.model), cost=\(format(cost))s error=\(error.localizedDescription)",
                    category: "ai_runtime"
                )
                throw error
            }
        }

        let client = AIClientFactory.makeClient(from: resolved)
        logger.debug(
            "准备调用 AI 推理，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), model=\(resolved.model), messages=\(effectiveRequest.messages.count), tools=\(effectiveRequest.tools.count)",
            category: "ai_runtime"
        )
        do {
            let response = try await gateway.generateText(client: client, request: effectiveRequest)
            let cost = Date().timeIntervalSince(start)
            logger.info(
                "AI 推理完成，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), model=\(response.model), cost=\(format(cost))s",
                category: "ai_runtime"
            )
            return response
        } catch {
            let cost = Date().timeIntervalSince(start)
            logger.error(
                "AI 推理失败，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), model=\(resolved.model), cost=\(format(cost))s error=\(error.localizedDescription)",
                category: "ai_runtime"
            )
            throw error
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
