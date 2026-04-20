import Foundation

/// AI 运行时服务协议
/// 定义流式文本生成的标准接口，遵循 Sendable 以支持并发环境
protocol AIRuntimeServing: Sendable {
    /// 发起流式文本生成请求
    /// - Parameter request: 文本请求参数
    /// - Returns: 异步抛出流，返回流式事件
    func generateTextStream(
        request: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error>
}

/// AI 运行时核心服务类
/// 统一调度云端模型 / 本地模型，处理工具调用降级、日志、推理路由
final class AIRuntimeService: AIRuntimeServing, @unchecked Sendable {
    // MARK: - 属性
    /// 配置中心：获取模型配置、厂商、参数
    private let configCenter: AIConfigCenter
    /// 云端网关：负责调用远程AI服务
    private let gateway: any AIRuntimeGateway
    /// 本地模型网关：负责调用GGUF本地模型（可选）
    private let localGateway: LocalGGUFTextGateway?
    /// 日志工具
    private let logger: Logger

    // MARK: - 初始化
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

    // MARK: - 流式推理入口
    /// 执行流式文本生成（核心方法）
    /// 自动路由：本地模型 → 云端模型；自动处理工具能力降级
    func generateTextStream(
        request: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error> {
        // 消息不能为空
        guard request.messages.isEmpty == false else {
            throw AIRuntimeError.emptyMessages
        }

        let start = Date()
        // 解析当前场景对应的模型配置
        let resolved = try await configCenter.resolve(
            for: request.scenario,
            preferredModelName: request.preferredModelName
        )
        // 获取当前模型配置快照
        let snapshot = await configCenter.currentSnapshot()
        // 判断模型是否支持工具调用（Function Call）
        let supportsToolUse = modelSupportsTools(modelName: resolved.model, snapshot: snapshot)
        // 从模型目录获取厂商名称（大写）
        let providerFromCatalog = snapshot.allModels.first(where: { $0.name == resolved.model })?.company.uppercased()
        let providerFromRequest = request.providerCompanyUppercased
        let mergedProvider = providerFromRequest ?? providerFromCatalog
        logger.debug(
            "AI provider 解析，scenario=\(request.scenario.rawValue), model=\(resolved.model), requestProvider=\(providerFromRequest ?? "<nil>"), catalogProvider=\(providerFromCatalog ?? "<nil>"), mergedProvider=\(mergedProvider ?? "<nil>"), modelInCatalog=\(providerFromCatalog != nil)",
            module: .aiConfig
        )
        
        // 构建最终请求：不支持工具的模型自动清空工具，降级为纯文本对话
        let effectiveRequest: AIRuntimeTextRequest = {
            guard supportsToolUse == false, request.tools.isEmpty == false else {
                return AIRuntimeTextRequest(
                    scenario: request.scenario,
                    messages: request.messages,
                    tools: request.tools,
                    toolChoice: request.toolChoice,
                    reasoning: request.reasoning,
                    preferredModelName: request.preferredModelName,
                    providerCompanyUppercased: request.providerCompanyUppercased ?? providerFromCatalog
                )
            }
            logger.info(
                "当前模型不支持 tools，已按严格模式降级为纯文本回合，model=\(resolved.model)",
                module: .aiConfig
            )
            return AIRuntimeTextRequest(
                scenario: request.scenario,
                messages: request.messages,
                tools: [],
                toolChoice: .none,
                reasoning: request.reasoning,
                preferredModelName: request.preferredModelName,
                providerCompanyUppercased: request.providerCompanyUppercased ?? providerFromCatalog
            )
        }()

        var effectiveMessages = effectiveRequest.messages
        if let selectedModel = snapshot.allModels.first(where: { $0.name == resolved.model }),
           selectedModel.identity == .agent,
           let prompt = selectedModel.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           prompt.isEmpty == false {
            effectiveMessages.insert(AIRuntimeMessage(role: .system, content: prompt), at: 0)
        }

        // MARK: - 优先使用本地模型
        if let localSelection = resolveLocalModelSelection(modelName: resolved.model, snapshot: snapshot) {
            // 必须有本地网关实例
            guard let localGateway else {
                throw LocalModelServiceError.modelLoadFailed
            }
            
            logger.debug(
                "准备调用本地模型流式推理，scenario=\(request.scenario.rawValue), model=\(resolved.model), messages=\(effectiveMessages.count), file=\(localSelection.fileName)",
                module: .aiConfig
            )
            
            // 调用本地模型
            let response = try await localGateway.generateText(
                fileName: localSelection.fileName,
                modelName: resolved.model,
                messages: effectiveMessages,
                maxTokens: resolved.maxTokens,
                temperature: resolved.temperature
            )
            
            let cost = Date().timeIntervalSince(start)
            logger.info(
                "本地模型推理完成（流式封装），scenario=\(request.scenario.rawValue), model=\(response.model), cost=\(format(cost))s",
                module: .aiConfig
            )
            
            // 记录输出日志
            AIRuntimeOutputLog.recordFinalModelOutput(
                scenario: request.scenario,
                inferenceSource: resolved.source.rawValue,
                response: response,
                logger: logger
            )
            
            // 包装为流式返回
            return AsyncThrowingStream { continuation in
                continuation.yield(.textDelta(response.text))
                continuation.yield(.completed(response))
                continuation.finish()
            }
        }

        // MARK: - 调用云端模型
        let client = AIClientFactory.makeClient(from: resolved)
        logger.debug(
            "准备调用 AI 流式推理，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), model=\(resolved.model), provider=\(effectiveRequest.providerCompanyUppercased ?? "<nil>"), messages=\(effectiveMessages.count), tools=\(effectiveRequest.tools.count)",
            module: .aiConfig
        )
        
        // 网关发起请求
        let upstream = try await gateway.generateTextStream(
            client: client,
            request: AIRuntimeTextRequest(
                scenario: effectiveRequest.scenario,
                messages: effectiveMessages,
                tools: effectiveRequest.tools,
                toolChoice: effectiveRequest.toolChoice,
                reasoning: effectiveRequest.reasoning,
                preferredModelName: effectiveRequest.preferredModelName,
                providerCompanyUppercased: effectiveRequest.providerCompanyUppercased
            )
        )
        
        // 包装并返回上流事件流
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var finalResponse: AIRuntimeTextResponse?
                    // 转发流式事件
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
                            module: .aiConfig
                        )
                        // 记录最终输出
                        AIRuntimeOutputLog.recordFinalModelOutput(
                            scenario: request.scenario,
                            inferenceSource: resolved.source.rawValue,
                            response: finalResponse,
                            logger: logger
                        )
                    } else {
                        logger.warning(
                            "AI 流式推理结束但缺少 completed 事件，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), cost=\(format(cost))s",
                            module: .aiConfig
                        )
                    }
                    continuation.finish()
                } catch {
                    let cost = Date().timeIntervalSince(start)
                    logger.error(
                        "AI 流式推理失败，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), model=\(resolved.model), cost=\(format(cost))s error=\(error.localizedDescription)",
                        module: .aiConfig
                    )
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - 内部工具方法
    /// 解析本地模型配置
    /// - 返回：模型文件名 + 模型对象（如果是本地模型）
    private func resolveLocalModelSelection(
        modelName: String,
        snapshot: AISettingsSnapshot
    ) -> (fileName: String, model: AllModels)? {
        // 查找对应模型
        guard let selected = snapshot.allModels.first(where: { $0.name == modelName }) else {
            return nil
        }
        // 仅本地厂商模型处理
        guard selected.company.uppercased() == LocalModelService.localCompany else {
            return nil
        }
        // 基础本地模型
        if selected.identity == .model, let fileName = selected.localFilename, fileName.isEmpty == false {
            return (fileName, selected)
        }
        // Agent 模型（使用基础模型文件）
        if selected.identity == .agent,
           let baseModelName = selected.baseModelName,
           let base = snapshot.allModels.first(where: { $0.name == baseModelName }),
           let fileName = base.localFilename,
           fileName.isEmpty == false {
            return (fileName, selected)
        }

        return nil
    }

    /// 判断模型是否支持工具调用（支持代理模型）
    private func modelSupportsTools(modelName: String, snapshot: AISettingsSnapshot) -> Bool {
        guard let selected = snapshot.allModels.first(where: { $0.name == modelName }) else {
            return false
        }
        // 代理模型检查自身 + 基础模型
        if selected.identity == .agent,
           let baseModelName = selected.baseModelName,
           let base = snapshot.allModels.first(where: { $0.name == baseModelName }) {
            return selected.supportsToolUse || base.supportsToolUse
        }
        return selected.supportsToolUse
    }

    /// 格式化耗时（保留3位小数）
    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }
}
