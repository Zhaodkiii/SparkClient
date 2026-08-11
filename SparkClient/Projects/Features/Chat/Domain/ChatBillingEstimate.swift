import Foundation

nonisolated enum ChatBillingPriceTier: Int, Sendable {
    case free = 0
    case economy = 1
    case standard = 2
    case premium = 3

    init(modelPriceTier: Int) {
        self = Self(rawValue: min(max(modelPriceTier, 0), 3)) ?? .free
    }

    var localizedTitle: String {
        switch self {
        case .free:
            return L10n.text("ai_settings.field.price_tier.free", fallback: "免费")
        case .economy:
            return L10n.text("ai_settings.field.price_tier.economy", fallback: "经济")
        case .standard:
            return L10n.text("ai_settings.field.price_tier.standard", fallback: "标准")
        case .premium:
            return L10n.text("ai_settings.field.price_tier.premium", fallback: "高级")
        }
    }

    /// Estimated blended model price per 1K tokens in USD.
    ///
    /// The project only stores a model price tier, not exact input/output prices
    /// or server-returned token usage. These values are deliberately coarse UI
    /// estimates for message cards.
    var estimatedUSDPerThousandTokens: Decimal {
        switch self {
        case .free:
            return 0
        case .economy:
            return Decimal(string: "0.00030") ?? 0
        case .standard:
            return Decimal(string: "0.00500") ?? 0
        case .premium:
            return Decimal(string: "0.03000") ?? 0
        }
    }
}

nonisolated enum ChatBillingCurrency: Sendable {
    case cny
    case usd

    static func current(locale: Locale = .current) -> ChatBillingCurrency {
        let region = locale.region?.identifier.uppercased()
            ?? locale.identifier.split(separator: "_").last.map { String($0).uppercased() }
        return region == "CN" ? .cny : .usd
    }

    var symbol: String {
        switch self {
        case .cny: return "¥"
        case .usd: return "$"
        }
    }

    var estimatedExchangeRateFromUSD: Decimal {
        switch self {
        case .cny: return Decimal(string: "7.20") ?? 7.2
        case .usd: return 1
        }
    }
}

nonisolated struct ChatBillingEstimate: Equatable, Sendable {
    let priceTier: ChatBillingPriceTier
    let promptTokens: Int
    let completionTokens: Int
    let estimatedTokens: Int
    let estimatedCalls: Int
    let currency: ChatBillingCurrency
    let estimatedAmount: Decimal

    init(
        priceTier: ChatBillingPriceTier,
        promptTokens: Int,
        completionTokens: Int,
        estimatedTokens: Int,
        estimatedCalls: Int,
        currency: ChatBillingCurrency,
        estimatedAmount: Decimal
    ) {
        self.priceTier = priceTier
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.estimatedTokens = estimatedTokens
        self.estimatedCalls = estimatedCalls
        self.currency = currency
        self.estimatedAmount = estimatedAmount
    }

    var isFree: Bool {
        priceTier == .free || estimatedAmount == 0
    }

    var formattedAmount: String {
        if isFree {
            return L10n.text("chat.billing.free", fallback: "免费")
        }
        let value = NSDecimalNumber(decimal: estimatedAmount).doubleValue
        let digits = value < 0.01 ? 4 : 2
        return "\(currency.symbol)\(String(format: "%.\(digits)f", value))"
    }

    var formattedTokens: String {
        if estimatedTokens >= 1_000 {
            return String(format: "%.1fk", Double(estimatedTokens) / 1_000.0)
        }
        return "\(estimatedTokens)"
    }

    var displayText: String {
        let tokenUnit = L10n.text("chat.billing.tokens", fallback: "tokens")
        let callUnit = L10n.text("chat.billing.calls", fallback: "calls")
        return "\(formattedAmount) · \(formattedTokens) \(tokenUnit) · \(estimatedCalls) \(callUnit)"
    }

    static func make(
        promptTokens: Int,
        completionTokens: Int,
        modelPriceTier: Int?,
        estimatedCalls: Int = 1,
        locale: Locale = .current
    ) -> ChatBillingEstimate {
        let tier = ChatBillingPriceTier(modelPriceTier: modelPriceTier ?? 0)
        let currency = ChatBillingCurrency.current(locale: locale)
        let normalizedPromptTokens = max(promptTokens, 0)
        let normalizedCompletionTokens = max(completionTokens, 0)
        let normalizedTokens = normalizedPromptTokens + normalizedCompletionTokens
        let usd = (Decimal(normalizedTokens) / Decimal(1_000)) * tier.estimatedUSDPerThousandTokens
        let amount = usd * currency.estimatedExchangeRateFromUSD
        return ChatBillingEstimate(
            priceTier: tier,
            promptTokens: normalizedPromptTokens,
            completionTokens: normalizedCompletionTokens,
            estimatedTokens: normalizedTokens,
            estimatedCalls: max(estimatedCalls, 1),
            currency: currency,
            estimatedAmount: amount
        )
    }

    static func make(summary: ChatMessageUsageSummary) -> ChatBillingEstimate {
        let currency: ChatBillingCurrency = summary.currencyCode.uppercased() == "CNY" ? .cny : .usd
        let visibleCallCount = summary.toolCallCount > 0 ? summary.toolCallCount : max(summary.llmCallCount, 1)
        return ChatBillingEstimate(
            priceTier: ChatBillingPriceTier(modelPriceTier: summary.priceTier),
            promptTokens: summary.promptTokens,
            completionTokens: summary.completionTokens,
            estimatedTokens: summary.totalTokens,
            estimatedCalls: visibleCallCount,
            currency: currency,
            estimatedAmount: summary.estimatedAmount
        )
    }

    static func make(
        message: ChatMessage,
        promptMessages: [ChatMessage],
        modelPriceTier: Int?,
        locale: Locale = .current
    ) -> ChatBillingEstimate {
        make(
            promptTokens: estimateTokens(textCharacterCount: promptMessages.promptCharacterCountForBilling),
            completionTokens: estimateTokens(textCharacterCount: message.completionCharacterCountForBilling),
            modelPriceTier: modelPriceTier,
            estimatedCalls: message.estimatedLLMCallCountForBilling,
            locale: locale
        )
    }

    static func estimateTokens(textCharacterCount: Int) -> Int {
        guard textCharacterCount > 0 else { return 0 }
        return max(1, Int(Double(textCharacterCount) / 3.5))
    }
}

private extension Array where Element == ChatMessage {
    nonisolated var promptCharacterCountForBilling: Int {
        reduce(0) { partial, message in
            partial + message.promptCharacterCountForBilling
        }
    }
}

private extension ChatMessage {
    nonisolated var promptCharacterCountForBilling: Int {
        blocks.reduce(0) { partial, block in
            partial + block.promptCharacterCountForBilling
        }
    }

    nonisolated var completionCharacterCountForBilling: Int {
        blocks.reduce(0) { partial, block in
            partial + block.completionCharacterCountForBilling
        }
    }

    nonisolated var estimatedLLMCallCountForBilling: Int {
        let toolBlockCount = blocks.filter { $0.kind == .tool }.count
        guard toolBlockCount > 0 else { return 1 }
        return max(2, toolBlockCount + 1)
    }
}

private extension ChatMessageBlock {
    nonisolated var promptCharacterCountForBilling: Int {
        switch payload {
        case .text(let text), .translatedText(let text), .html(let text), .error(let text):
            return text.count
        case .deepThought(let card):
            return card.reasoningContent?.count ?? 0
        case .tool(let tool):
            return tool.billableCharacterCount
        case .assistantStatusCard(let card):
            return card.message.count
        default:
            return text?.count ?? 0
        }
    }

    nonisolated var completionCharacterCountForBilling: Int {
        switch payload {
        case .text(let text), .translatedText(let text), .html(let text), .error(let text):
            return text.count
        case .deepThought(let card):
            return card.reasoningContent?.count ?? 0
        case .tool(let tool):
            return tool.billableCharacterCount
        case .assistantStatusCard(let card):
            return card.message.count
        default:
            return text?.count ?? 0
        }
    }
}

private extension ChatToolBlockPayload {
    nonisolated var billableCharacterCount: Int {
        var total = 0
        total += name?.count ?? 0
        total += content.count
        if let invocationArguments, invocationArguments.isEmpty == false {
            total += invocationArguments
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: "\n")
                .count
        }
        return total
    }
}
