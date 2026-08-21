import Foundation

/// 引导卡片科普问题生成状态。
nonisolated enum ChatGuideQuestionGenerationState: String, Codable, Equatable, Sendable {
    /// 固定 preset 问题（未绑定成员或兼容旧卡片）
    case preset
    /// AI 生成进行中
    case generating
    /// AI 生成成功
    case generated
    /// AI 失败后的 preset 兜底
    case fallback
    /// 生成失败（应快速转为 fallback）
    case failed
}

/// 引导卡片科普问题生成元数据。
nonisolated struct ChatGuideQuestionGenerationMeta: Codable, Equatable, Sendable {
    var state: ChatGuideQuestionGenerationState
    var source: String?
    var memberID: Int?
    var memberProfileDigest: String?
    var generatedAt: Date?
    var errorMessage: String?

    nonisolated init(
        state: ChatGuideQuestionGenerationState,
        source: String? = nil,
        memberID: Int? = nil,
        memberProfileDigest: String? = nil,
        generatedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.state = state
        self.source = source
        self.memberID = memberID
        self.memberProfileDigest = memberProfileDigest
        self.generatedAt = generatedAt
        self.errorMessage = errorMessage
    }
}

/// 对话引导卡片 payload：新会话首条 system 消息的完整数据。
/// 上半部分为可横向切换的健康数据滑块（`metricSections`），
/// 下半部分为健康科普问题列表（`questions`）。
nonisolated struct ChatGuideCardPayload: Codable, Equatable, Sendable {
    /// payload 结构版本，用于后续结构演进时的兼容判断。
    var schemaVersion: Int
    /// payload 构建时间（引导卡片生成时刻）。
    var generatedAt: Date
    /// 构建时选中的成员 ID（nil 表示未指定成员）。
    var memberID: Int?
    /// 健康数据滑块 section 列表（运动/身材/饮食/医疗）。
    var metricSections: [ChatGuideMetricSection]
    /// 健康科普问题列表。
    var questions: [ChatGuideQuestion]
    /// 科普问题生成状态（schema v2+）。
    var questionGeneration: ChatGuideQuestionGenerationMeta?

    nonisolated init(
        schemaVersion: Int,
        generatedAt: Date,
        memberID: Int?,
        metricSections: [ChatGuideMetricSection],
        questions: [ChatGuideQuestion],
        questionGeneration: ChatGuideQuestionGenerationMeta? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.memberID = memberID
        self.metricSections = metricSections
        self.questions = questions
        self.questionGeneration = questionGeneration
    }

    /// 健康滑块是页面实时数据，不属于消息快照。
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKey.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .key("schemaVersion")) ?? 1
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .key("generatedAt")) ?? Date()
        memberID = try container.decodeIfPresent(Int.self, forKey: .key("memberID"))
        questions = try container.decodeIfPresent([ChatGuideQuestion].self, forKey: .key("questions")) ?? []
        questionGeneration = try container.decodeIfPresent(
            ChatGuideQuestionGenerationMeta.self,
            forKey: .key("questionGeneration")
        )
        metricSections = []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodableKey.self)
        try container.encode(schemaVersion, forKey: .key("schemaVersion"))
        try container.encode(generatedAt, forKey: .key("generatedAt"))
        try container.encodeIfPresent(memberID, forKey: .key("memberID"))
        try container.encode(questions, forKey: .key("questions"))
        try container.encodeIfPresent(questionGeneration, forKey: .key("questionGeneration"))
    }

    /// 有效生成状态：旧 payload 无 meta 时按 questions 推断。
    nonisolated var effectiveQuestionGenerationState: ChatGuideQuestionGenerationState {
        if let state = questionGeneration?.state {
            return state
        }
        return questions.isEmpty ? .generating : .preset
    }

    /// 是否应展示问题区 loading（覆盖旧问题，禁止点击）。
    nonisolated var isShowingQuestionLoading: Bool {
        switch effectiveQuestionGenerationState {
        case .generating:
            return true
        case .failed:
            return questions.isEmpty
        case .preset, .generated, .fallback:
            return false
        }
    }

    /// 当前问题是否属于指定 thread 绑定成员。
    nonisolated func questionsBelongTo(memberID: Int?) -> Bool {
        guard let memberID else {
            return questionGeneration?.memberID == nil
        }
        return questionGeneration?.memberID == memberID
    }
}

/// 引导卡片数据滑块的数据类别。
nonisolated enum ChatGuideMetricCategory: String, Codable, Equatable, Sendable {
    case movement
    case bodyManagement
    case nutrition
    case medical
}

/// 数据 section 的可用状态（决定空态/授权入口/失败态展示）。
nonisolated enum ChatGuideMetricSectionState: String, Codable, Equatable, Sendable {
    /// 数据完整可用
    case ready
    /// 部分数据可用
    case partial
    /// 未授权（展示去绑定/授权入口）
    case unauthorized
    /// 无数据（展示暂无数据）
    case empty
    /// 数据读取失败（轻量失败态，不阻塞卡片）
    case failed
    /// 能力不可用（设备不支持等）
    case unavailable
}

/// 数据 section 的可选操作（如去绑定/去授权）。
nonisolated struct ChatGuideMetricAction: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Equatable, Sendable {
        /// 跳转 Apple 健康授权
        case bindHealth
        /// 跳转医疗资料模块
        case openMedical
    }

    var kind: Kind
    /// 展示文案（已本地化后的快照文本）。
    var title: String
}

/// 迷你趋势图（sparkline）：仅存归一化后的形状值。
nonisolated struct ChatGuideMiniChart: Codable, Equatable, Sendable {
    /// 归一化到 0...1 的趋势值序列。
    var normalizedValues: [Double]

    nonisolated init(normalizedValues: [Double]) {
        self.normalizedValues = normalizedValues
    }

    nonisolated static func normalized(from values: [Double]) -> ChatGuideMiniChart? {
        guard values.count >= 2 else { return nil }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let range = maxValue - minValue
        guard range > 0 else {
            return ChatGuideMiniChart(normalizedValues: values.map { _ in 0.5 })
        }
        return ChatGuideMiniChart(
            normalizedValues: values.map { ($0 - minValue) / range }
        )
    }
}

/// 数据滑块单个 section（如"运动数据"一屏）。
nonisolated struct ChatGuideMetricSection: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var category: ChatGuideMetricCategory
    /// section 标题（如"运动数据"）。
    var title: String
    /// 副标题（如"今日 · 最近更新 08:30"）。
    var subtitle: String?
    /// 指标条目（每屏最多 3 个）。
    var items: [ChatGuideMetricItem]
    /// 可选迷你趋势图。
    var chart: ChatGuideMiniChart?
    /// 空态/未授权时的操作入口。
    var action: ChatGuideMetricAction?
    var state: ChatGuideMetricSectionState

    nonisolated init(
        id: String,
        category: ChatGuideMetricCategory,
        title: String,
        subtitle: String? = nil,
        items: [ChatGuideMetricItem] = [],
        chart: ChatGuideMiniChart? = nil,
        action: ChatGuideMetricAction? = nil,
        state: ChatGuideMetricSectionState
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.chart = chart
        self.action = action
        self.state = state
    }
}

/// 数据滑块单个指标（如"步数 10000 步"）。
nonisolated struct ChatGuideMetricItem: Identifiable, Codable, Equatable, Sendable {
    var id: String
    /// 指标名（如"步数"）。
    var title: String
    /// 主数值文本（已格式化，如"10000"）。
    var valueText: String
    /// 单位文本（如"步"），与主数值分行展示。
    var unitText: String?
    /// SF Symbol 或色板名（预留轻量着色）。
    var tintName: String

    nonisolated init(
        id: String,
        title: String,
        valueText: String,
        unitText: String? = nil,
        tintName: String = "accent"
    ) {
        self.id = id
        self.title = title
        self.valueText = valueText
        self.unitText = unitText
        self.tintName = tintName
    }
}

/// 引导卡片科普问题：展示文案短，发送给 AI 的 prompt 更完整。
nonisolated struct ChatGuideQuestion: Identifiable, Codable, Equatable, Sendable {
    var id: String
    /// 列表展示文案。
    var title: String
    /// 点击后发送给 AI 的完整 prompt。
    var prompt: String
    /// 问题分类标识（如 `popular_science`）。
    var category: String

    nonisolated init(id: String, title: String, prompt: String, category: String) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.category = category
    }
}

/// 第一阶段固定三条健康科普问题预设。
nonisolated enum ChatGuideQuestionPreset {
    nonisolated static let phaseOne: [ChatGuideQuestion] = [
        ChatGuideQuestion(
            id: "tcm_medicine_precautions",
            title: L10n.text(
                "chat.guide.question.tcm_medicine_precautions.title",
                fallback: "使用中成药有哪些注意事项?"
            ),
            prompt: "使用中成药有哪些注意事项?",
            category: "popular_science"
        ),
        ChatGuideQuestion(
            id: "astragalus_suitable_groups",
            title: L10n.text(
                "chat.guide.question.astragalus_suitable_groups.title",
                fallback: "黄芪适合哪些人群服用?"
            ),
            prompt: "黄芪适合哪些人群服用?",
            category: "popular_science"
        ),
        ChatGuideQuestion(
            id: "lactose_intolerance_handling",
            title: L10n.text(
                "chat.guide.question.lactose_intolerance_handling.title",
                fallback: "乳糖不耐受如何处理?"
            ),
            prompt: "乳糖不耐受如何处理?",
            category: "popular_science"
        )
    ]
}
