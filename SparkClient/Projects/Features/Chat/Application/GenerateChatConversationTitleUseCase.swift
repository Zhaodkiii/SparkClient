import Foundation

struct GenerateChatConversationTitleUseCase: Sendable {
    let repository: any ChatRepository
    let orchestrator: ChatOrchestrator
    let aiConfigCenter: AIConfigCenter
    let logger: Logger

    struct Request: Sendable {
        let threadID: UUID
        let messages: [ChatMessage]
        let currentTitle: String
        let isRegenerate: Bool
        let preferredModelName: String?
        let languageCode: String?
    }

    struct Result: Sendable {
        let title: String
        let source: ChatConversationTitleSource
        let thread: ChatThread
    }

    enum SkipReason: String, Sendable {
        case notPlaceholder = "not_placeholder"
        case regenerate = "regenerate"
        case missingUser = "missing_user"
        case missingAssistant = "missing_assistant"
        case awaitingUserInput = "awaiting_user_input"
    }

    func callAsFunction(_ request: Request) async throws -> Result? {
        if request.isRegenerate {
            logSkip(threadID: request.threadID, reason: .regenerate)
            return nil
        }
        guard ChatSessionTitle.isPlaceholder(request.currentTitle) else {
            logSkip(threadID: request.threadID, reason: .notPlaceholder)
            return nil
        }

        guard let context = collectFirstTurnContext(from: request.messages) else {
            if request.messages.contains(where: { $0.role == .user && $0.isTombstone == false }) == false {
                logSkip(threadID: request.threadID, reason: .missingUser)
            } else {
                logSkip(threadID: request.threadID, reason: .missingAssistant)
            }
            return nil
        }

        if context.hasPendingAskUser {
            logSkip(threadID: request.threadID, reason: .awaitingUserInput)
            return nil
        }

        let zh = ChatSessionTitle.isChinese(languageCode: request.languageCode)
        let (generatedTitle, source) = await generateTitle(
            threadID: request.threadID,
            firstUser: context.firstUser,
            firstAssistant: context.firstAssistant,
            preferredModelName: request.preferredModelName,
            chinese: zh
        )

        guard generatedTitle.isEmpty == false else { return nil }
        await repository.updateThreadTitle(threadID: request.threadID, title: generatedTitle)
        guard let updated = await repository.loadThread(id: request.threadID) else { return nil }
        logger.info(
            "Chat 会话标题已生成，thread=\(shortID(request.threadID)), title=\(generatedTitle), source=\(source.rawValue)",
            module: .general
        )
        return Result(title: generatedTitle, source: source, thread: updated)
    }

    private struct FirstTurnContext: Sendable {
        let firstUser: String
        let firstAssistant: String
        let hasPendingAskUser: Bool
    }

    private func collectFirstTurnContext(from messages: [ChatMessage]) -> FirstTurnContext? {
        let visible = messages
            .filter { $0.role != .system && $0.isTombstone == false }
            .sorted { $0.createdAt < $1.createdAt }

        guard let firstUser = visible.first(where: { $0.role == .user }) else { return nil }
        let userContent = resolvedMessageContent(firstUser)
        guard userContent.isEmpty == false else { return nil }

        let assistants = visible.filter { $0.role == .assistant && $0.createdAt >= firstUser.createdAt }
        guard let firstAssistant = assistants.first else { return nil }
        guard firstAssistant.deliveryState == .sent ||
            firstAssistant.deliveryState == .read ||
            firstAssistant.deliveryState == .failed
        else {
            return nil
        }

        let pendingAskUser = firstAssistant.blocks.contains { block in
            if block.kind == .pendingMemberToolCards { return block.status != .ready }
            return block.status == .pending || block.status == .streaming
        }
        if pendingAskUser {
            return FirstTurnContext(firstUser: userContent, firstAssistant: "", hasPendingAskUser: true)
        }

        let assistantContent = resolvedMessageContent(firstAssistant)
        guard assistantContent.isEmpty == false else { return nil }

        return FirstTurnContext(
            firstUser: userContent,
            firstAssistant: assistantContent,
            hasPendingAskUser: false
        )
    }

    private func resolvedMessageContent(_ message: ChatMessage) -> String {
        let text = message.blocks
            .sorted { lhs, rhs in
                switch (lhs.orderKey, rhs.orderKey) {
                case let (l?, r?) where l != r: return l < r
                case (.some, nil): return true
                case (nil, .some): return false
                default: return lhs.createdAt < rhs.createdAt
                }
            }
            .compactMap { block -> String? in
                guard block.nodeRole == .timeline else { return nil }
                guard let text = block.text?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false else {
                    return nil
                }
                return text
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    private func generateTitle(
        threadID: UUID,
        firstUser: String,
        firstAssistant: String,
        preferredModelName: String?,
        chinese: Bool
    ) async -> (String, ChatConversationTitleSource) {
        let start = Date()
        let resolvedConfig: AIResolvedConfig
        do {
            resolvedConfig = try await aiConfigCenter.resolve(
                for: .chat,
                preferredModelName: preferredModelName
            )
        } catch {
            logger.warning(
                "Chat 会话标题模型解析失败，thread=\(shortID(threadID)), error=\(error.localizedDescription)",
                module: .general
            )
            return (ChatSessionTitle.fallbackTitle(from: firstUser), .fallbackFromUserMessage)
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
            \(ChatSessionTitle.clipText(firstUser, limit: 800))

            [助手]
            \(ChatSessionTitle.clipText(firstAssistant, limit: 1500))
            """
        } else {
            systemPrompt = """
            You generate a concise, descriptive title for a conversation. Output only the title as plain text — no quotes, no markdown, no trailing punctuation, no "Title:" prefix. Keep it 4-8 words.
            """
            userPrompt = """
            Generate a title for this conversation:

            [User]
            \(ChatSessionTitle.clipText(firstUser, limit: 800))

            [Assistant]
            \(ChatSessionTitle.clipText(firstAssistant, limit: 1500))
            """
        }

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
                    threadID: threadID,
                    inference: inference,
                    systemPrompt: systemPrompt,
                    preferredModelName: preferredModelName ?? resolvedConfig.model,
                    temperature: 0.3,
                    maxTokens: 80
                )
            }
            let sanitized = ChatSessionTitle.sanitizeSessionTitle(output.text)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            if sanitized.isEmpty == false {
                logger.debug(
                    "Chat 会话标题生成完成，thread=\(shortID(threadID)), durationMs=\(durationMs)",
                    module: .general
                )
                return (sanitized, .autoGenerated)
            }
            return (ChatSessionTitle.fallbackTitle(from: firstUser), .fallbackFromUserMessage)
        } catch is TimeoutError {
            logger.warning("Chat 会话标题生成超时，thread=\(shortID(threadID))", module: .general)
            return (ChatSessionTitle.fallbackTitle(from: firstUser), .fallbackFromUserMessage)
        } catch {
            logger.warning(
                "Chat 会话标题生成失败，thread=\(shortID(threadID)), error=\(error.localizedDescription)",
                module: .general
            )
            return (ChatSessionTitle.fallbackTitle(from: firstUser), .fallbackFromUserMessage)
        }
    }

    private func logSkip(threadID: UUID, reason: SkipReason) {
        logger.debug(
            "Chat 会话标题跳过，thread=\(shortID(threadID)), reason=\(reason.rawValue)",
            module: .general
        )
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
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
