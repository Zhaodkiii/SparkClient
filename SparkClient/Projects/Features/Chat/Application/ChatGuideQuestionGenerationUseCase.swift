import Foundation

struct ChatGuideQuestionGenerationInput: Sendable {
    var threadID: UUID
    var messageID: UUID
    var blockID: UUID
    var memberID: Int
    var localeIdentifier: String
    var modelName: String?
    var metricSections: [ChatGuideMetricSection]
}

struct ChatGuideQuestionGenerationOutput: Sendable {
    var questions: [ChatGuideQuestion]
    var memberID: Int
    var memberProfileDigest: String
    var source: String
    var generatedAt: Date
}

enum ChatGuideQuestionGenerationUseCaseError: Error, Equatable {
    case memberProfileUnavailable
    case aiGenerationFailed
    case parseFailed(stage: ChatGuideQuestionJSONParserStage, parserError: String, rawLength: Int)
    case cancelled
}

struct ChatGuideQuestionGenerationUseCase: Sendable {
    let runtime: AIRuntimeServing
    let medicalReader: any ChatGuideMedicalReading
    let promptLocalizer: PromptLocalizer
    let logger: Logger

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

    func generate(input: ChatGuideQuestionGenerationInput) async throws -> ChatGuideQuestionGenerationOutput {
        let profileResult = await medicalReader.fetchMemberCompleteData(memberID: input.memberID)
        guard case .success(let completeData) = profileResult else {
            throw ChatGuideQuestionGenerationUseCaseError.memberProfileUnavailable
        }

        let memberProfileSummary = await MainActor.run {
            ChatGuideMemberProfilePromptFormatter.makeProfileSummary(data: completeData)
        }
        let metricSummary = ChatGuideMemberProfilePromptFormatter.makeMetricSummary(sections: input.metricSections)
        let digest = ChatGuideMemberProfilePromptFormatter.makeProfileDigest(
            memberID: input.memberID,
            data: completeData
        )

        let prompt = promptLocalizer.chatGuideQuestionGenerationPrompt(
            localeIdentifier: input.localeIdentifier,
            metricSummary: metricSummary,
            memberProfileSummary: memberProfileSummary
        )

        // CHAT-000028 3.1：解码失败不再走 repair 修复链路，直接抛 parseFailed，
        // 由 coordinator 立即使用固定三条问题兜底（不重复发起 AI 请求）。
        let rawText = try await runGeneration(prompt: prompt, modelName: input.modelName)
        do {
            let questions = try ChatGuideQuestionJSONParser.parse(rawText)
            return makeOutput(questions: questions, memberID: input.memberID, digest: digest)
        } catch let parseError as ChatGuideQuestionJSONParserError {
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
            throw mapUnexpectedError(error)
        }
    }

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

    private func runGeneration(prompt: String, modelName: String?) async throws -> String {
        let request = AIRuntimeTextRequest(
            scenario: .chat,
            messages: [AIRuntimeMessage(role: .user, content: prompt)],
            tools: [],
            toolChoice: .none,
            reasoning: .disabled,
            preferredModelName: modelName,
            temperature: 0.7,
            topP: 0.9,
            maxTokens: 800
        )
        do {
            return try await collectResponseText(from: try await runtime.generateTextStream(request: request))
        } catch is CancellationError {
            throw ChatGuideQuestionGenerationUseCaseError.cancelled
        } catch {
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

    private func collectResponseText(
        from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>
    ) async throws -> String {
        var bufferedText = ""
        var completedText: String?
        do {
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case .textDelta(let delta):
                    bufferedText.append(delta)
                case .completed(let response):
                    completedText = response.text
                case .reasoningDelta, .toolCallDelta:
                    continue
                }
            }
        } catch is CancellationError {
            throw ChatGuideQuestionGenerationUseCaseError.cancelled
        } catch {
            if Task.isCancelled {
                throw ChatGuideQuestionGenerationUseCaseError.cancelled
            }
            throw error
        }

        let text = completedText ?? bufferedText
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ChatGuideQuestionGenerationUseCaseError.aiGenerationFailed
        }
        return text
    }

    private func mapUnexpectedError(_ error: Error) -> ChatGuideQuestionGenerationUseCaseError {
        if let useCaseError = error as? ChatGuideQuestionGenerationUseCaseError {
            return useCaseError
        }
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        return .aiGenerationFailed
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
