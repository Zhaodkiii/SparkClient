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
        try request.cancellationToken?.checkCancellation()

        let start = Date()
        // 解析当前场景对应的模型配置
        let resolved = try await configCenter.resolve(
            for: request.scenario,
            preferredModelName: request.preferredModelName
        )
        let bundles = try await configCenter.effectiveScenarioBundles()
        let allRows = bundles.allRows
        // 判断模型是否支持工具调用（Function Call）
        let supportsToolUse = modelSupportsTools(modelName: resolved.model, allRows: allRows)
        // 从模型目录获取厂商名称（大写）
        let selectedCatalogModel = allRows.first(where: { $0.name == resolved.model })
        let providerFromCatalog = selectedCatalogModel?.providerID
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
                    providerCompanyUppercased: request.providerCompanyUppercased ?? providerFromCatalog,
                    temperature: request.temperature,
                    topP: request.topP,
                    maxTokens: request.maxTokens,
                    cancellationToken: request.cancellationToken
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
                providerCompanyUppercased: request.providerCompanyUppercased ?? providerFromCatalog,
                temperature: request.temperature,
                topP: request.topP,
                maxTokens: request.maxTokens,
                cancellationToken: request.cancellationToken
            )
        }()

        let effectiveMessages = effectiveRequest.messages

        // MARK: - 优先使用本地模型
        if let localSelection = resolveLocalModelSelection(modelName: resolved.model, allRows: allRows) {
            // 必须有本地网关实例
            guard let localGateway else {
                throw LocalModelServiceError.modelLoadFailed
            }
            
            logger.debug(
                "准备调用本地模型流式推理，scenario=\(request.scenario.rawValue), model=\(resolved.model), messages=\(effectiveMessages.count), file=\(localSelection.fileName)",
                module: .aiConfig
            )
            
            // 调用本地模型。这里返回真正的流，取消时会向下触发 `llm.stop()`。
            let responseStream = try await localGateway.generateTextStream(
                fileName: localSelection.fileName,
                modelName: resolved.model,
                messages: effectiveMessages,
                maxTokens: effectiveRequest.maxTokens ?? resolved.maxTokens,
                temperature: effectiveRequest.temperature ?? resolved.temperature,
                cancellationToken: effectiveRequest.cancellationToken
            )

            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        var finalResponse: AIRuntimeTextResponse?
                        for try await event in responseStream {
                            try effectiveRequest.cancellationToken?.checkCancellation()
                            if case .completed(let response) = event {
                                finalResponse = response
                            }
                            continuation.yield(event)
                        }

                        let cost = Date().timeIntervalSince(start)
                        if let finalResponse {
                            logger.info(
                                "本地模型流式推理完成，scenario=\(request.scenario.rawValue), model=\(finalResponse.model), cost=\(format(cost))s",
                                module: .aiConfig
                            )
                            AIRuntimeOutputLog.recordFinalModelOutput(
                                scenario: request.scenario,
                                inferenceSource: resolved.source.rawValue,
                                response: finalResponse,
                                logger: logger
                            )
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        logger.info(
                            "本地模型流式推理已取消，scenario=\(request.scenario.rawValue), model=\(resolved.model)",
                            module: .aiConfig
                        )
                        continuation.finish(throwing: CancellationError())
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { termination in
                    self.logger.debug(
                        "本地模型 Runtime 流结束，termination=\(termination), scenario=\(request.scenario.rawValue), model=\(resolved.model)",
                        module: .aiConfig
                    )
                    // `onTermination` 在正常 finish 时也会触发；只有消费者主动取消时才向下传播取消信号。
                    if case .cancelled = termination {
                        effectiveRequest.cancellationToken?.cancel()
                        task.cancel()
                    }
                }
            }
        }

        // 对「智能体（agent）」类型模型做特殊处理：
        // - 对外调用厂商 API 时：使用其绑定的「基座模型名」（baseModelName）
        // - 对内系统逻辑：仍然使用 agent 名称（用于目录查找、Prompt 注入、策略控制等）
        //
        // 目的：实现「Agent 抽象层」与「底层模型调用」解耦
        // 例如：agent = 写作助手 → 实际调用 qwen / gpt 等具体模型
        let resolvedForAPI: AIResolvedConfig = {
            // 条件：当前选择的模型是 agent，并且存在合法的 baseModelName
            guard let selectedCatalogModel,
                  selectedCatalogModel.identity == AIModelIdentity.agent.rawValue,
                  let baseModelName = selectedCatalogModel.baseModelName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  baseModelName.isEmpty == false
            else {
                // 非 agent 或未配置基座模型 → 直接使用原始配置
                return resolved
            }

            // 构造新的配置：仅替换 model 字段，其它保持不变
            return AIResolvedConfig(
                endpoint: resolved.endpoint,
                model: baseModelName,   // ⚠️ 关键：这里替换为真实调用的底层模型
                apiKey: resolved.apiKey,
                temperature: resolved.temperature,
                maxTokens: resolved.maxTokens,
                source: resolved.source
            )
        }()
        
        // MARK: - 调用云端模型
        let client = AIClientFactory.makeClient(
            from: resolvedForAPI,
            temperatureOverride: effectiveRequest.temperature,
            topPOverride: effectiveRequest.topP,
            maxTokensOverride: effectiveRequest.maxTokens
        )
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
                providerCompanyUppercased: effectiveRequest.providerCompanyUppercased,
                temperature: effectiveRequest.temperature,
                topP: effectiveRequest.topP,
                maxTokens: effectiveRequest.maxTokens,
                cancellationToken: effectiveRequest.cancellationToken
            )
        )
        
        // 包装并返回上流事件流
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var finalResponse: AIRuntimeTextResponse?
                    // 转发流式事件
                    for try await event in upstream {
                        try effectiveRequest.cancellationToken?.checkCancellation()
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
                } catch is CancellationError {
                    let cost = Date().timeIntervalSince(start)
                    logger.info(
                        "AI 流式推理已取消，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), model=\(resolved.model), cost=\(format(cost))s",
                        module: .aiConfig
                    )
                    continuation.finish(throwing: CancellationError())
                } catch {
                    let cost = Date().timeIntervalSince(start)
                    logger.error(
                        "AI 流式推理失败，scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), model=\(resolved.model), cost=\(format(cost))s error=\(error.localizedDescription)",
                        module: .aiConfig
                    )
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { termination in
                if AIRuntimeDebugFlags.verboseStreamLogs {
                    self.logger.debug(
                        "AI Runtime 流结束，termination=\(termination), scenario=\(request.scenario.rawValue), source=\(resolved.source.rawValue), model=\(resolved.model)",
                        module: .aiConfig
                    )
                }
                // 正常完成也会回调 onTermination，不能把 `.finished` 误当用户停止。
                if case .cancelled = termination {
                    effectiveRequest.cancellationToken?.cancel()
                    task.cancel()
                }
            }
        }
    }

    // MARK: - 内部工具方法
    /// 解析本地模型配置
    /// - 返回：模型文件名 + 模型对象（如果是本地模型）
    private func resolveLocalModelSelection(
        modelName: String,
        allRows: [AIScenarioRemoteModelRow]
    ) -> (fileName: String, row: AIScenarioRemoteModelRow)? {
        // 查找对应模型
        guard let selected = allRows.first(where: { $0.name == modelName }) else {
            return nil
        }
        // 仅本地厂商模型处理
        guard AIProviderAdapterRegistry.adapter(for: selected.providerID).isLocal else {
            return nil
        }
        // 基础本地模型
        if selected.identity == AIModelIdentity.model.rawValue,
           let fileName = selected.localFilename,
           fileName.isEmpty == false
        {
            return (fileName, selected)
        }
        // Agent 模型（使用基础模型文件）
        if selected.identity == AIModelIdentity.agent.rawValue,
           let baseModelName = selected.baseModelName,
           let base = allRows.first(where: { $0.name == baseModelName }),
           let fileName = base.localFilename,
           fileName.isEmpty == false {
            return (fileName, selected)
        }

        return nil
    }

    /// 判断模型是否支持工具调用（支持代理模型）
    private func modelSupportsTools(modelName: String, allRows: [AIScenarioRemoteModelRow]) -> Bool {
        guard let selected = allRows.first(where: { $0.name == modelName }) else {
            return false
        }
        // 代理模型检查自身 + 基础模型
        if selected.identity == AIModelIdentity.agent.rawValue,
           let baseModelName = selected.baseModelName,
           let base = allRows.first(where: { $0.name == baseModelName }) {
            return selected.supportsToolUse || base.supportsToolUse
        }
        return selected.supportsToolUse
    }

    /// 格式化耗时（保留3位小数）
    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }
}
