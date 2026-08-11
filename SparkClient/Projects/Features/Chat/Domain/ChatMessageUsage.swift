import Foundation

nonisolated enum ChatUsageSource: String, Codable, Equatable, Sendable {
    case providerUsage
    case localFallbackEstimate
    case serverComputed
    case migratedEstimate
}

nonisolated enum ChatUsageEventType: String, Codable, Equatable, Sendable {
    case llmRequestStarted
    case llmUsageReceived
    case llmUsageEstimated
    case toolCallStarted
    case toolCallFinished
    case assistantCompleted
    case assistantFailed
}

nonisolated struct ChatMessageUsageSummary: Codable, Equatable, Sendable {
    let id: UUID
    let messageID: UUID
    let threadID: UUID
    let modelName: String?
    let priceTier: Int
    let currencyCode: String
    let promptTokens: Int
    let completionTokens: Int
    let reasoningTokens: Int
    let cachedPromptTokens: Int
    let totalTokens: Int
    let llmCallCount: Int
    let toolCallCount: Int
    let estimatedAmount: Decimal
    let isEstimated: Bool
    let source: ChatUsageSource
    let createdAt: Date
    let updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        messageID: UUID,
        threadID: UUID,
        modelName: String?,
        priceTier: Int,
        currencyCode: String,
        promptTokens: Int,
        completionTokens: Int,
        reasoningTokens: Int = 0,
        cachedPromptTokens: Int = 0,
        totalTokens: Int? = nil,
        llmCallCount: Int,
        toolCallCount: Int,
        estimatedAmount: Decimal,
        isEstimated: Bool,
        source: ChatUsageSource,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.messageID = messageID
        self.threadID = threadID
        self.modelName = modelName
        self.priceTier = priceTier
        self.currencyCode = currencyCode
        self.promptTokens = max(promptTokens, 0)
        self.completionTokens = max(completionTokens, 0)
        self.reasoningTokens = max(reasoningTokens, 0)
        self.cachedPromptTokens = max(cachedPromptTokens, 0)
        self.totalTokens = max(totalTokens ?? (promptTokens + completionTokens + reasoningTokens), 0)
        self.llmCallCount = max(llmCallCount, 0)
        self.toolCallCount = max(toolCallCount, 0)
        self.estimatedAmount = estimatedAmount
        self.isEstimated = isEstimated
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct ChatMessageUsageEvent: Codable, Equatable, Sendable {
    let id: UUID
    let messageID: UUID
    let threadID: UUID
    let runID: UUID?
    let eventType: ChatUsageEventType
    let callIndex: Int
    let modelName: String?
    let toolCallID: String?
    let toolName: String?
    let promptTokens: Int
    let completionTokens: Int
    let reasoningTokens: Int
    let cachedPromptTokens: Int
    let totalTokens: Int
    let isEstimated: Bool
    let createdAt: Date

    nonisolated init(
        id: UUID = UUID(),
        messageID: UUID,
        threadID: UUID,
        runID: UUID?,
        eventType: ChatUsageEventType,
        callIndex: Int,
        modelName: String?,
        toolCallID: String? = nil,
        toolName: String? = nil,
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        reasoningTokens: Int = 0,
        cachedPromptTokens: Int = 0,
        totalTokens: Int? = nil,
        isEstimated: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.messageID = messageID
        self.threadID = threadID
        self.runID = runID
        self.eventType = eventType
        self.callIndex = max(callIndex, 0)
        self.modelName = modelName
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.promptTokens = max(promptTokens, 0)
        self.completionTokens = max(completionTokens, 0)
        self.reasoningTokens = max(reasoningTokens, 0)
        self.cachedPromptTokens = max(cachedPromptTokens, 0)
        self.totalTokens = max(totalTokens ?? (promptTokens + completionTokens + reasoningTokens), 0)
        self.isEstimated = isEstimated
        self.createdAt = createdAt
    }
}
