import Foundation

/// 聊天引导问题生成用例的输入参数
/// - Note: 遵循 Sendable 协议，支持并发安全传递
struct ChatGuideQuestionGenerationInput: Sendable {
    /// 会话线程 ID
    var threadID: UUID
    /// 消息 ID
    var messageID: UUID
    /// 消息块 ID
    var blockID: UUID
    /// 成员 ID
    var memberID: Int
    /// 本地化标识符，用于多语言 prompt 生成
    var localeIdentifier: String
    /// 指定使用的 AI 模型名称，可选
    var modelName: String?
    /// 健康指标数据分组
    var metricSections: [ChatGuideMetricSection]
}

/// 聊天引导问题生成用例的输出结果
/// - Note: 遵循 Sendable 协议，支持并发安全传递
struct ChatGuideQuestionGenerationOutput: Sendable {
    /// AI 生成的引导问题列表
    var questions: [ChatGuideQuestion]
    /// 成员 ID
    var memberID: Int
    /// 成员画像摘要指纹，用于缓存和去重
    var memberProfileDigest: String
    /// 问题来源标识，固定为 "current_chat_ai" 表示当前会话 AI 生成
    var source: String
    /// 问题生成时间戳
    var generatedAt: Date
}

/// 聊天引导问题生成过程中可能出现的错误类型
/// - Note: 遵循 Equatable 协议，便于错误比对和测试
enum ChatGuideQuestionGenerationUseCaseError: Error, Equatable {
    /// 成员画像数据不可用，无法获取完整健康数据
    case memberProfileUnavailable
    /// AI 生成请求失败（网络错误、模型异常、空响应等）
    case aiGenerationFailed
    /// JSON 解析失败
    /// - Parameters:
    ///   - stage: 解析阶段（初始解析/修复重试等）
    ///   - parserError: 解析器错误分类信息
    ///   - rawLength: 原始响应文本长度
    case parseFailed(stage: ChatGuideQuestionJSONParserStage, parserError: String, rawLength: Int)
    /// 任务被取消
    case cancelled
}

/// 聊天引导问题生成用例
/// - Important: 核心业务逻辑：基于成员健康画像和指标数据，通过 AI 生成个性化的聊天引导问题
/// - Note: 遵循 Sendable 协议，支持在并发环境中安全使用
struct ChatGuideQuestionGenerationUseCase: Sendable {
    /// AI 运行时服务，用于发起文本生成请求
    let runtime: AIRuntimeServing
    /// 医疗数据读取器，用于获取成员完整健康数据
    let medicalReader: any ChatGuideMedicalReading
    /// Prompt 本地化器，用于生成多语言提示词
    let promptLocalizer: PromptLocalizer
    /// 日志记录器
    let logger: Logger

    /// 初始化引导问题生成用例
    /// - Parameters:
    ///   - runtime: AI 运行时服务
    ///   - medicalReader: 医疗数据读取器
    ///   - promptLocalizer: Prompt 本地化器，默认使用 PromptLocalizer()
    ///   - logger: 日志记录器，默认使用 ConsoleLogger()
    init(
        runtime: AIRuntimeServing,
        medicalReader: any ChatGuideMedicalReading,
        promptLocalizer: PromptLocalizer = PromptLocalizer(),
        logger: Logger = ConsoleLogger()
    ) {
        self.runtime = runtime
        self.medicalReader = medicalReader
        self.promptLocalizer = promptLocalizer
        self.logger = logger
    }

    /// 执行引导问题生成主流程
    /// - Parameter input: 生成输入参数
    /// - Returns: 生成结果，包含问题列表和元数据
    /// - Throws: ChatGuideQuestionGenerationUseCaseError 中定义的各类错误
    /// - Important: CHAT-000028 需求：解码失败不再走 repair 修复链路，直接抛 parseFailed，由 coordinator 立即使用固定三条问题兜底（不重复发起 AI 请求）
    func generate(input: ChatGuideQuestionGenerationInput) async throws -> ChatGuideQuestionGenerationOutput {
        // 1. 获取成员完整健康画像数据
        let profileResult = await medicalReader.fetchMemberCompleteData(memberID: input.memberID)
        guard case .success(let completeData) = profileResult else {
            throw ChatGuideQuestionGenerationUseCaseError.memberProfileUnavailable
        }

        // 2. 构建 Prompt 所需的各类摘要数据
        // 成员画像摘要（在主线程执行，因为可能涉及 UI 相关数据格式化）
        let memberProfileSummary = await MainActor.run {
            ChatGuideMemberProfilePromptFormatter.makeProfileSummary(data: completeData)
        }
        // 健康指标摘要
        let metricSummary = ChatGuideMemberProfilePromptFormatter.makeMetricSummary(sections: input.metricSections)
        // 成员画像指纹（用于缓存标识）
        let digest = ChatGuideMemberProfilePromptFormatter.makeProfileDigest(
            memberID: input.memberID,
            data: completeData
        )

        // 3. 生成本地化的 Prompt
        let prompt = promptLocalizer.chatGuideQuestionGenerationPrompt(
            localeIdentifier: input.localeIdentifier,
            metricSummary: metricSummary,
            memberProfileSummary: memberProfileSummary
        )

        // 4. 调用 AI 生成原始文本
        let rawText = try await runGeneration(prompt: prompt, modelName: input.modelName)
        
        // 5. 解析 JSON 响应
        do {
            let questions = try ChatGuideQuestionJSONParser.parse(rawText)
            return makeOutput(questions: questions, memberID: input.memberID, digest: digest)
        } catch let parseError as ChatGuideQuestionJSONParserError {
            // 解析失败时记录日志并向上抛出错误
            logParseFailure(
                threadID: input.threadID,
                stage: .initial,
                error: parseError,
                rawLength: rawText.count
            )
            throw ChatGuideQuestionGenerationUseCaseError.parseFailed(
                stage: .initial,
                parserError: ChatGuideQuestionJSONParser.errorCategory(for: parseError),
                rawLength: rawText.count
            )
        } catch {
            // 其他未知错误统一映射
            throw mapUnexpectedError(error)
        }
    }

    /// 构建生成输出结果
    /// - Parameters:
    ///   - questions: 解析后的问题列表
    ///   - memberID: 成员 ID
    ///   - digest: 成员画像指纹
    /// - Returns: 标准化的输出对象
    private func makeOutput(
        questions: [ChatGuideQuestion],
        memberID: Int,
        digest: String
    ) -> ChatGuideQuestionGenerationOutput {
        ChatGuideQuestionGenerationOutput(
            questions: questions,
            memberID: memberID,
            memberProfileDigest: digest,
            source: "current_chat_ai",
            generatedAt: Date()
        )
    }

    /// 记录 JSON 解析失败日志
    /// - Parameters:
    ///   - threadID: 会话线程 ID
    ///   - stage: 解析阶段
    ///   - error: 解析错误
    ///   - rawLength: 原始文本长度
    private func logParseFailure(
        threadID: UUID,
        stage: ChatGuideQuestionJSONParserStage,
        error: ChatGuideQuestionJSONParserError,
        rawLength: Int
    ) {
        logger.debug(
            "chat.guide.questions.parse_failed thread=\(shortID(threadID)) stage=\(stage.rawValue) parserError=\(ChatGuideQuestionJSONParser.errorCategory(for: error)) rawLength=\(rawLength)",
            module: .general
        )
    }

    /// 执行 AI 文本生成请求
    /// - Parameters:
    ///   - prompt: 提示词文本
    ///   - modelName: 指定模型名称，可选
    /// - Returns: AI 生成的原始文本
    /// - Throws: aiGenerationFailed 或 cancelled 错误
    private func runGeneration(prompt: String, modelName: String?) async throws -> String {
        // 构建 AI 请求参数
        let request = AIRuntimeTextRequest(
            scenario: .chat,
            messages: [AIRuntimeMessage(role: .user, content: prompt)],
            tools: [],
            toolChoice: .none,
            reasoning: .disabled, // 关闭思考链，直接输出结果
            preferredModelName: modelName,
            temperature: 0.7, // 适中的随机性，保证问题多样性同时不偏离主题
            topP: 0.9,
            maxTokens: 800 // 限制输出长度，避免过长响应
        )
        do {
            // 发起流式请求并收集完整响应
            return try await collectResponseText(from: try await runtime.generateTextStream(request: request))
        } catch is CancellationError {
            throw ChatGuideQuestionGenerationUseCaseError.cancelled
        } catch {
            // 双重检查取消状态，避免遗漏
            if Task.isCancelled {
                throw ChatGuideQuestionGenerationUseCaseError.cancelled
            }
            logger.debug(
                "引导卡片科普问题 AI 生成失败：\(error.localizedDescription)",
                module: .general
            )
            throw ChatGuideQuestionGenerationUseCaseError.aiGenerationFailed
        }
    }

    /// 从流式响应中收集完整文本
    /// - Parameter stream: AI 流式事件流
    /// - Returns: 拼接后的完整文本
    /// - Throws: 网络错误、取消错误或 aiGenerationFailed（空响应）
    private func collectResponseText(
        from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>
    ) async throws -> String {
        // 增量文本缓冲区
        var bufferedText = ""
        // 完成事件携带的完整文本（优先使用，避免增量拼接丢失）
        var completedText: String?
        
        do {
            // 遍历流式事件
            for try await event in stream {
                // 每次迭代检查取消状态
                try Task.checkCancellation()
                switch event {
                case .textDelta(let delta):
                    // 增量文本追加到缓冲区
                    bufferedText.append(delta)
                case .completed(let response):
                    // 收到完成事件，保存完整文本
                    completedText = response.text
                case .reasoningDelta, .toolCallDelta:
                    // 忽略思考过程和工具调用事件
                    continue
                }
            }
        } catch is CancellationError {
            throw ChatGuideQuestionGenerationUseCaseError.cancelled
        } catch {
            // 双重检查取消状态
            if Task.isCancelled {
                throw ChatGuideQuestionGenerationUseCaseError.cancelled
            }
            throw error
        }

        // 优先使用完成事件的文本，降级使用增量拼接的缓冲区
        let text = completedText ?? bufferedText
        // 校验响应非空
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ChatGuideQuestionGenerationUseCaseError.aiGenerationFailed
        }
        return text
    }

    /// 将未知错误映射为标准的用例错误
    /// - Parameter error: 原始错误
    /// - Returns: 映射后的 ChatGuideQuestionGenerationUseCaseError
    private func mapUnexpectedError(_ error: Error) -> ChatGuideQuestionGenerationUseCaseError {
        // 如果已经是标准错误直接返回
        if let useCaseError = error as? ChatGuideQuestionGenerationUseCaseError {
            return useCaseError
        }
        // 处理取消错误
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        // 其他错误统一归类为生成失败
        return .aiGenerationFailed
    }

    /// 生成 UUID 的短标识符（前 8 位），用于日志输出
    /// - Parameter id: 完整 UUID
    /// - Returns: 8 位短 ID 字符串
    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
