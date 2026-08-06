import Foundation

nonisolated enum DeepTutorToolIntentDomain: String, Sendable, Codable {
    case casualChat = "casual_chat"
    case knowledgeQA = "knowledge_qa"
    case askUserExplicit = "ask_user_explicit"
    case weatherLocation = "weather_location"
    case healthData = "health_data"
    case healthReport = "health_report"
    case knowledgeBag = "knowledge_bag"
    case webSearch = "web_search"
}

nonisolated enum DeepTutorHealthDataSubdomain: String, Sendable, Codable {
    case sleep
    case steps
    case energy
    case nutrition
    case workout
    case general
}

nonisolated enum DeepTutorToolIntentTimeRange: String, Sendable, Codable {
    case recent
    case today
    case week
    case month
    case explicitDate = "explicit_date"
    case unknown
}

nonisolated enum DeepTutorToolIntentConfidence: String, Sendable, Codable {
    case high
    case medium
    case low
}

/// 结构化意图槽位：用于 Spark domain extension 工具面决策与日志复现。
nonisolated struct DeepTutorStructuredToolIntent: Equatable, Sendable, Codable {
    var domain: DeepTutorToolIntentDomain
    var subdomain: DeepTutorHealthDataSubdomain?
    var timeRange: DeepTutorToolIntentTimeRange
    var dateAnchor: String?
    var memberRequirement: Bool
    var confidence: DeepTutorToolIntentConfidence

    nonisolated var logLabel: String {
        let sub = subdomain?.rawValue ?? "-"
        let date = dateAnchor ?? "-"
        return "\(domain.rawValue)/\(sub)/\(timeRange.rawValue)/\(date)"
    }
}

/// 将用户输入升级为结构化意图槽位（关键词只产出 slot，不直接挂载工具）。
enum DeepTutorToolIntentClassifier: Sendable {
    nonisolated static func classify(
        userInput: String,
        capability: DeepTutorCapability
    ) -> [DeepTutorStructuredToolIntent] {
        let normalized = normalize(userInput)
        guard normalized.isEmpty == false else { return [] }

        var intents: [DeepTutorStructuredToolIntent] = []
        let dateAnchor = extractDateAnchor(from: userInput)
        let timeRange = extractTimeRange(from: normalized, hasExplicitDate: dateAnchor != nil)

        if matchesAny(normalized, patterns: casualChatPatterns) {
            intents.append(
                DeepTutorStructuredToolIntent(
                    domain: .casualChat,
                    subdomain: nil,
                    timeRange: .unknown,
                    dateAnchor: nil,
                    memberRequirement: false,
                    confidence: .medium
                )
            )
        }
        if matchesAny(normalized, patterns: askUserExplicitPatterns) {
            intents.append(
                DeepTutorStructuredToolIntent(
                    domain: .askUserExplicit,
                    subdomain: nil,
                    timeRange: .unknown,
                    dateAnchor: nil,
                    memberRequirement: false,
                    confidence: .high
                )
            )
        }
        if matchesAny(normalized, patterns: weatherLocationPatterns) {
            intents.append(
                DeepTutorStructuredToolIntent(
                    domain: .weatherLocation,
                    subdomain: nil,
                    timeRange: timeRange,
                    dateAnchor: dateAnchor,
                    memberRequirement: false,
                    confidence: .high
                )
            )
        }
        if matchesAny(normalized, patterns: healthDataPatterns) {
            intents.append(
                DeepTutorStructuredToolIntent(
                    domain: .healthData,
                    subdomain: healthSubdomain(from: normalized),
                    timeRange: timeRange,
                    dateAnchor: dateAnchor,
                    memberRequirement: true,
                    confidence: .high
                )
            )
        }
        if matchesAny(normalized, patterns: healthReportPatterns) {
            intents.append(
                DeepTutorStructuredToolIntent(
                    domain: .healthReport,
                    subdomain: nil,
                    timeRange: timeRange,
                    dateAnchor: dateAnchor,
                    memberRequirement: true,
                    confidence: .medium
                )
            )
        }
        if matchesAny(normalized, patterns: knowledgeBagPatterns) {
            intents.append(
                DeepTutorStructuredToolIntent(
                    domain: .knowledgeBag,
                    subdomain: nil,
                    timeRange: .unknown,
                    dateAnchor: nil,
                    memberRequirement: false,
                    confidence: .high
                )
            )
        }
        if matchesAny(normalized, patterns: webSearchPatterns) {
            intents.append(
                DeepTutorStructuredToolIntent(
                    domain: .webSearch,
                    subdomain: nil,
                    timeRange: timeRange,
                    dateAnchor: dateAnchor,
                    memberRequirement: false,
                    confidence: .medium
                )
            )
        }

        let hasBlockingDomain = intents.contains {
            switch $0.domain {
            case .casualChat, .weatherLocation, .healthData, .healthReport, .webSearch:
                return true
            default:
                return false
            }
        }
        if hasBlockingDomain == false, matchesAny(normalized, patterns: knowledgeQAPatterns) {
            intents.append(
                DeepTutorStructuredToolIntent(
                    domain: .knowledgeQA,
                    subdomain: nil,
                    timeRange: .unknown,
                    dateAnchor: nil,
                    memberRequirement: false,
                    confidence: .medium
                )
            )
        }

        if capability == .masteryPath, intents.isEmpty {
            intents.append(
                DeepTutorStructuredToolIntent(
                    domain: .knowledgeQA,
                    subdomain: nil,
                    timeRange: .unknown,
                    dateAnchor: nil,
                    memberRequirement: false,
                    confidence: .low
                )
            )
        }

        return intents
    }

    nonisolated static func hintLabels(from intents: [DeepTutorStructuredToolIntent]) -> [String] {
        intents.map(\.domain.rawValue)
    }

    nonisolated static func healthSubdomain(from normalizedInput: String) -> DeepTutorHealthDataSubdomain {
        if matchesAny(normalizedInput, patterns: sleepPatterns) { return .sleep }
        if matchesAny(normalizedInput, patterns: stepsPatterns) { return .steps }
        if matchesAny(normalizedInput, patterns: energyPatterns) { return .energy }
        if matchesAny(normalizedInput, patterns: nutritionPatterns) { return .nutrition }
        if matchesAny(normalizedInput, patterns: workoutPatterns) { return .workout }
        return .general
    }

    // MARK: - Parsing helpers

    private nonisolated static func extractDateAnchor(from userInput: String) -> String? {
        // 今天是20260806 / 2026-08-06 / 2026/08/06
        let compact = #"(\d{4})(\d{2})(\d{2})"#
        if let match = firstMatch(in: userInput, pattern: compact),
           match.count == 4 {
            return "\(match[1])-\(match[2])-\(match[3])"
        }
        let dashed = #"(\d{4})[-/](\d{1,2})[-/](\d{1,2})"#
        if let match = firstMatch(in: userInput, pattern: dashed),
           match.count == 4 {
            let month = match[2].count == 1 ? "0\(match[2])" : match[2]
            let day = match[3].count == 1 ? "0\(match[3])" : match[3]
            return "\(match[1])-\(month)-\(day)"
        }
        return nil
    }

    private nonisolated static func extractTimeRange(
        from normalized: String,
        hasExplicitDate: Bool
    ) -> DeepTutorToolIntentTimeRange {
        // 语义时间词优先于裸日期锚点（例如「最近…今天是20260806」）。
        if matchesAny(normalized, patterns: ["今天", "今日", "today"]) { return .today }
        if matchesAny(normalized, patterns: ["本周", "这周", "最近一周", "一周", "this week", "week"]) {
            return .week
        }
        if matchesAny(normalized, patterns: ["本月", "这个月", "最近一个月", "month"]) {
            return .month
        }
        if matchesAny(normalized, patterns: ["最近", "近期", "recently", "recent"]) {
            return .recent
        }
        if hasExplicitDate { return .explicitDate }
        return .unknown
    }

    private nonisolated static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var parts: [String] = []
        for index in 0..<match.numberOfRanges {
            guard let subRange = Range(match.range(at: index), in: text) else { return nil }
            parts.append(String(text[subRange]))
        }
        return parts
    }

    private nonisolated static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private nonisolated static func matchesAny(_ normalizedInput: String, patterns: [String]) -> Bool {
        patterns.contains { normalizedInput.contains($0) }
    }

    private nonisolated static let casualChatPatterns = [
        "你好", "您好", "嗨", "哈喽", "hello", "hi", "hey",
        "哈哈", "嘿嘿", "在吗", "早安", "晚安", "谢谢", "多谢", "morning",
    ]

    private nonisolated static let knowledgeQAPatterns = [
        "解释", "讲讲", "为什么", "怎么理解", "如何理解", "什么是", "是什么",
        "explain", "what is", "how does", "tell me about", "帮我理解",
    ]

    private nonisolated static let askUserExplicitPatterns = [
        "先问我", "你问我", "需要我提供", "问一下我", "ask me", "ask me first",
        "先使用工具", "问问我在",
    ]

    private nonisolated static let weatherLocationPatterns = [
        "天气", "气温", "weather", "下雨", "温度", "forecast",
        "附近", "路线", "导航", "定位", "在哪", "哪个城市", "city",
    ]

    private nonisolated static let healthDataPatterns = [
        "步数", "睡眠", "运动", "饮食", "营养", "能量", "锻炼", "走路", "卡路里",
        "sleep", "steps", "workout", "nutrition", "energy",
    ]

    private nonisolated static let sleepPatterns = ["睡眠", "睡觉", "sleep"]
    private nonisolated static let stepsPatterns = ["步数", "走路", "steps", "walking"]
    private nonisolated static let energyPatterns = ["能量", "卡路里", "热量", "energy", "calorie"]
    private nonisolated static let nutritionPatterns = ["饮食", "营养", "nutrition", "food", "meal"]
    private nonisolated static let workoutPatterns = ["运动", "锻炼", "workout", "exercise"]

    private nonisolated static let healthReportPatterns = [
        "报告", "检查", "病历", "化验", "体检", "资料", "检验",
    ]

    private nonisolated static let knowledgeBagPatterns = [
        "知识库", "knowledge base", "kb",
    ]

    private nonisolated static let webSearchPatterns = [
        "搜索", "最新", "新闻", "论文", "arxiv", "网页", "查一下", "search", "google", "lookup",
    ]
}
