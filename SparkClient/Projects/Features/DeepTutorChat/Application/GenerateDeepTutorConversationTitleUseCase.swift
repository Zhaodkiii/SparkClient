import Foundation

struct GenerateDeepTutorConversationTitleUseCase: Sendable {
    let repository: any DeepTutorLocalChatRepository
    let orchestrator: ChatOrchestrator
    let aiConfigCenter: AIConfigCenter
    let logger: Logger

    struct Request: Sendable {
        let conversationID: UUID
        let messages: [DeepTutorMessage]
        let currentTitle: String
        let isRegenerate: Bool
        let preferredModelName: String?
        let languageCode: String?
    }

    struct Result: Sendable {
        let title: String
        let source: DeepTutorConversationTitleSource
        let conversation: DeepTutorConversation
    }

    enum SkipReason: String, Sendable {
        case notPlaceholder = "not_placeholder"
        case regenerate = "regenerate"
        case missingUser = "missing_user"
        case missingAssistant = "missing_assistant"
        case awaitingUserInput = "awaiting_user_input"
        case alreadyGenerated = "already_generated"
    }

    func callAsFunction(_ request: Request) async throws -> Result? {
        let conversationShortID = DeepTutorChatLog.shortID(request.conversationID)
        DeepTutorChatLog.titleMaybeStart(
            conversationID: request.conversationID,
            currentTitle: request.currentTitle,
            isPlaceholder: DeepTutorSessionTitle.isPlaceholder(request.currentTitle),
            messageCount: request.messages.count,
            isRegenerate: request.isRegenerate
        )

        if request.isRegenerate {
            DeepTutorChatLog.titleMaybeSkipped(conversationID: request.conversationID, reason: .regenerate)
            return nil
        }
        guard DeepTutorSessionTitle.isPlaceholder(request.currentTitle) else {
            DeepTutorChatLog.titleMaybeSkipped(conversationID: request.conversationID, reason: .notPlaceholder)
            return nil
        }

        guard let context = collectFirstTurnContext(from: request.messages) else {
            if request.messages.contains(where: { $0.role == .user }) == false {
                DeepTutorChatLog.titleMaybeSkipped(conversationID: request.conversationID, reason: .missingUser)
            } else {
                DeepTutorChatLog.titleMaybeSkipped(conversationID: request.conversationID, reason: .missingAssistant)
            }
            return nil
        }

        if context.hasPendingAskUser {
            DeepTutorChatLog.titleMaybeSkipped(conversationID: request.conversationID, reason: .awaitingUserInput)
            return nil
        }

        DeepTutorChatLog.titleContextCollected(
            conversationID: request.conversationID,
            firstUserLength: context.firstUser.count,
            firstAssistantLength: context.firstAssistant.count
        )

        let zh = DeepTutorSessionTitle.isChinese(languageCode: request.languageCode)
        let (generatedTitle, source) = await generateTitle(
            conversationID: request.conversationID,
            firstUser: context.firstUser,
            firstAssistant: context.firstAssistant,
            preferredModelName: request.preferredModelName,
            chinese: zh
        )

        let updated = try await repository.updateConversationTitle(
            id: request.conversationID,
            title: generatedTitle,
            source: source
        )
        DeepTutorChatLog.titlePersistDone(
            conversationID: request.conversationID,
            oldTitle: request.currentTitle,
            newTitle: generatedTitle,
            source: source
        )
        logger.info(
            "DeepTutor 会话标题已生成，conversation=\(conversationShortID), title=\(generatedTitle), source=\(source.rawValue)",
            module: DeepTutorChatLog.module
        )
        return Result(title: generatedTitle, source: source, conversation: updated)
    }

    private struct FirstTurnContext: Sendable {
        let firstUser: String
        let firstAssistant: String
        let hasPendingAskUser: Bool
    }

    private func collectFirstTurnContext(from messages: [DeepTutorMessage]) -> FirstTurnContext? {
        let visible = messages
            .filter { $0.role != .system && $0.isDeleted == false }
            .sorted { $0.createdAt < $1.createdAt }

        guard let firstUser = visible.first(where: { $0.role == .user }) else { return nil }
        let userContent = firstUser.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard userContent.isEmpty == false else { return nil }

        let assistants = visible.filter { $0.role == .assistant && $0.createdAt >= firstUser.createdAt }
        guard let firstAssistant = assistants.first else { return nil }
        guard firstAssistant.status == .ready || firstAssistant.status == .failed else { return nil }

        let pendingAskUser = firstAssistant.blocks.contains { block in
            if case let .askUser(payload) = block.payload { return payload.isResolved == false }
            return false
        }
        if pendingAskUser { return FirstTurnContext(firstUser: userContent, firstAssistant: "", hasPendingAskUser: true) }

        let assistantContent = resolvedAssistantContent(firstAssistant)
        guard assistantContent.isEmpty == false else { return nil }

        return FirstTurnContext(
            firstUser: userContent,
            firstAssistant: assistantContent,
            hasPendingAskUser: false
        )
    }

    private func resolvedAssistantContent(_ message: DeepTutorMessage) -> String {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false { return trimmed }
        return message.events.compactMap { event -> String? in
            if case let .contentDelta(text, _, _) = event { return text }
            return nil
        }.joined()
    }

    private func generateTitle(
        conversationID: UUID,
        firstUser: String,
        firstAssistant: String,
        preferredModelName: String?,
        chinese: Bool
    ) async -> (String, DeepTutorConversationTitleSource) {
        let start = Date()
        let resolvedConfig: AIResolvedConfig
        do {
            resolvedConfig = try await aiConfigCenter.resolve(
                for: .chat,
                preferredModelName: preferredModelName
            )
        } catch {
            DeepTutorChatLog.titleLLMFailed(
                conversationID: conversationID,
                error: error.localizedDescription
            )
            let fallback = DeepTutorSessionTitle.fallbackTitle(from: firstUser)
            DeepTutorChatLog.titleFallback(conversationID: conversationID, fallbackTitle: fallback)
            return (fallback, .fallbackFromUserMessage)
        }

        let systemPrompt: String
        let userPrompt: String
        if chinese {
            systemPrompt = """
            你需要为一段对话生成一个简洁的标题。
            直接输出标题文本，不要引号、不要 Markdown 格式、
            不要末尾标点、不要 "标题：" 这类前缀。
            标题控制在 4-10 个汉字以内。
            """
            userPrompt = """
            请基于以下对话生成标题：

            [用户]
            \(DeepTutorSessionTitle.clipText(firstUser, limit: 800))

            [助手]
            \(DeepTutorSessionTitle.clipText(firstAssistant, limit: 1500))
            """
        } else {
            systemPrompt = """
            You generate a concise, descriptive title for a conversation. Output only the title as plain text — no quotes, no markdown, no trailing punctuation, no "Title:" prefix. Keep it 4-8 words.
            """
            userPrompt = """
            Generate a title for this conversation:

            [User]
            \(DeepTutorSessionTitle.clipText(firstUser, limit: 800))

            [Assistant]
            \(DeepTutorSessionTitle.clipText(firstAssistant, limit: 1500))
            """
        }

        DeepTutorChatLog.titleLLMStart(
            conversationID: conversationID,
            model: resolvedConfig.model,
            language: chinese ? "zh" : "en"
        )

        let inference = ChatOrchestratorInferenceOptions(
            useTools: false,
            useKnowledgeBag: false,
            useWebSearch: false,
            reasoningEnabled: false,
            reasoningEffortTier: 0,
            allowedToolNames: nil
        )

        do {
            let output = try await withTimeout(seconds: 20) {
                try await orchestrator.generateReply(
                    userInput: userPrompt,
                    history: [],
                    memberContextSummary: "",
                    memberID: nil,
                    threadID: conversationID,
                    inference: inference,
                    systemPrompt: systemPrompt,
                    preferredModelName: preferredModelName ?? resolvedConfig.model,
                    temperature: 0.3,
                    maxTokens: 80
                )
            }
            let rawTitle = output.text
            DeepTutorChatLog.titleLLMRaw(conversationID: conversationID, rawTitle: rawTitle)
            let sanitized = DeepTutorSessionTitle.sanitizeSessionTitle(rawTitle)
            DeepTutorChatLog.titleSanitized(conversationID: conversationID, sanitizedTitle: sanitized)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            if sanitized.isEmpty == false {
                DeepTutorChatLog.titleLLMDone(conversationID: conversationID, durationMs: durationMs)
                return (sanitized, .autoGenerated)
            }
            let fallback = DeepTutorSessionTitle.fallbackTitle(from: firstUser)
            DeepTutorChatLog.titleFallback(conversationID: conversationID, fallbackTitle: fallback)
            return (fallback, .fallbackFromUserMessage)
        } catch is TimeoutError {
            DeepTutorChatLog.titleLLMTimeout(conversationID: conversationID)
            let fallback = DeepTutorSessionTitle.fallbackTitle(from: firstUser)
            DeepTutorChatLog.titleFallback(conversationID: conversationID, fallbackTitle: fallback)
            return (fallback, .fallbackFromUserMessage)
        } catch {
            DeepTutorChatLog.titleLLMFailed(conversationID: conversationID, error: error.localizedDescription)
            let fallback = DeepTutorSessionTitle.fallbackTitle(from: firstUser)
            DeepTutorChatLog.titleFallback(conversationID: conversationID, fallbackTitle: fallback)
            return (fallback, .fallbackFromUserMessage)
        }
    }

    private struct TimeoutError: Error {}

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
