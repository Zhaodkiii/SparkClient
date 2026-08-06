import Foundation

// MARK: - Payload

nonisolated enum DeepTutorQuizSource: String, Codable, Sendable {
    case streaming
    case result
    case contentParser = "content_parser"
    case legacy
}

nonisolated struct DeepTutorQuizParseErrorPayload: Codable, Equatable, Sendable {
    var title: String
    var message: String
    var reason: String
    var messageID: UUID

    init(
        title: String = "问答结构解析失败",
        message: String = "题目数据未能解析为可交互卡片，请重新生成。",
        reason: String,
        messageID: UUID
    ) {
        self.title = title
        self.message = message
        self.reason = reason
        self.messageID = messageID
    }
}

nonisolated struct DeepTutorQuizPayload: Codable, Equatable, Sendable {
    var id: String?
    var title: String
    var turnID: String?
    var questions: [DeepTutorQuizQuestion]
    var source: DeepTutorQuizSource

    init(
        id: String? = nil,
        title: String = "Quick Check",
        turnID: String? = nil,
        questions: [DeepTutorQuizQuestion],
        source: DeepTutorQuizSource = .streaming
    ) {
        self.id = id
        self.title = title
        self.turnID = turnID
        self.questions = questions
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case turnID
        case turnId
        case questions
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Quick Check"
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
            ?? container.decodeIfPresent(String.self, forKey: .turnId)
        questions = try container.decodeIfPresent([DeepTutorQuizQuestion].self, forKey: .questions) ?? []
        source = try container.decodeIfPresent(DeepTutorQuizSource.self, forKey: .source) ?? .legacy
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(turnID, forKey: .turnID)
        try container.encode(questions, forKey: .questions)
        try container.encode(source, forKey: .source)
    }
}

// MARK: - Question

nonisolated enum DeepTutorQuizQuestionType: String, Codable, Sendable, CaseIterable {
    case choice
    case concept
    case fillInBlank = "fill_in_blank"
    case shortAnswer = "short_answer"
    case written
    case coding

    var displayLabel: String {
        switch self {
        case .choice: return "Multiple Choice"
        case .concept: return "Concept Question"
        case .fillInBlank: return "Fill in the Blank"
        case .shortAnswer: return "Short Answer"
        case .written: return "Essay"
        case .coding: return "Coding"
        }
    }

    static func normalize(_ raw: String?) -> DeepTutorQuizQuestionType {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "choice", "multiple_choice", "mcq": return .choice
        case "concept", "true_false", "tf", "judgement", "judgment": return .concept
        case "fill_in_blank", "fill_in_the_blank", "cloze": return .fillInBlank
        case "short_answer": return .shortAnswer
        case "written", "open_ended", "open_response", "essay": return .written
        case "coding", "code", "programming": return .coding
        default: return .shortAnswer
        }
    }

    /// Resolve type with options available — promote to choice when options exist.
    static func resolve(
        raw: String?,
        options: [DeepTutorQuizOption],
        questionID: String
    ) -> DeepTutorQuizQuestionType {
        let rawNormalized = normalize(raw)
        if options.count >= 2 {
            let keys = Set(options.map { $0.key.uppercased() })
            let looksLikeConcept = keys.isSubset(of: ["TRUE", "FALSE", "对", "错", "T", "F"])
            if looksLikeConcept {
                if rawNormalized != .concept {
                    DeepTutorChatLog.quizQuestionTypeResolved(
                        questionID: questionID,
                        rawType: raw,
                        resolvedType: DeepTutorQuizQuestionType.concept.rawValue,
                        optionCount: options.count,
                        reason: "options_look_like_true_false"
                    )
                }
                return .concept
            }
            if rawNormalized != .choice {
                DeepTutorChatLog.quizQuestionTypeResolved(
                    questionID: questionID,
                    rawType: raw,
                    resolvedType: DeepTutorQuizQuestionType.choice.rawValue,
                    optionCount: options.count,
                    reason: "options_present_promote_choice"
                )
            }
            return .choice
        }

        if rawNormalized == .choice, options.isEmpty {
            DeepTutorChatLog.quizQuestionTypeFallback(
                questionID: questionID,
                rawType: raw,
                fallbackType: DeepTutorQuizQuestionType.shortAnswer.rawValue,
                reason: "choice_without_options"
            )
            return .shortAnswer
        }

        if raw == nil || (raw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) {
            DeepTutorChatLog.quizQuestionTypeFallback(
                questionID: questionID,
                rawType: raw,
                fallbackType: DeepTutorQuizQuestionType.choice.rawValue,
                reason: "missing_type_default_choice"
            )
            return .choice
        }

        if rawNormalized == .shortAnswer {
            DeepTutorChatLog.quizQuestionTypeFallback(
                questionID: questionID,
                rawType: raw,
                fallbackType: DeepTutorQuizQuestionType.shortAnswer.rawValue,
                reason: "explicit_short_answer_no_options"
            )
        } else {
            DeepTutorChatLog.quizQuestionTypeResolved(
                questionID: questionID,
                rawType: raw,
                resolvedType: rawNormalized.rawValue,
                optionCount: options.count,
                reason: "raw_type"
            )
        }
        return rawNormalized
    }
}

nonisolated struct DeepTutorQuizOption: Codable, Equatable, Sendable, Identifiable {
    var key: String
    var text: String

    var id: String { key }
}

nonisolated struct DeepTutorQuizQuestion: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var question: String
    var questionType: DeepTutorQuizQuestionType
    var options: [DeepTutorQuizOption]
    var correctAnswer: String
    var explanation: String
    var difficulty: String?
    var concentration: String?
    var knowledgeContext: String?

    enum CodingKeys: String, CodingKey {
        case id
        case questionID = "question_id"
        case question
        case prompt
        case questionType = "question_type"
        case options
        case correctAnswer = "correct_answer"
        case correctIndex
        case explanation
        case difficulty
        case concentration
        case knowledgeContext = "knowledge_context"
    }

    init(
        id: String,
        question: String,
        questionType: DeepTutorQuizQuestionType,
        options: [DeepTutorQuizOption] = [],
        correctAnswer: String,
        explanation: String = "",
        difficulty: String? = nil,
        concentration: String? = nil,
        knowledgeContext: String? = nil
    ) {
        self.id = id
        self.question = question
        self.questionType = questionType
        self.options = options
        self.correctAnswer = correctAnswer
        self.explanation = explanation
        self.difficulty = difficulty
        self.concentration = concentration
        self.knowledgeContext = knowledgeContext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .questionID)
            ?? UUID().uuidString
        question = try container.decodeIfPresent(String.self, forKey: .question)
            ?? container.decodeIfPresent(String.self, forKey: .prompt)
            ?? ""
        let rawQuestionType = try container.decodeIfPresent(String.self, forKey: .questionType)

        if let keyedOptions = try? container.decode([String: String].self, forKey: .options) {
            options = keyedOptions
                .sorted { $0.key < $1.key }
                .map { DeepTutorQuizOption(key: $0.key.uppercased(), text: $0.value) }
        } else if let legacyOptions = try? container.decode([String].self, forKey: .options) {
            options = legacyOptions.enumerated().map { index, text in
                DeepTutorQuizOption(key: String(UnicodeScalar(65 + index)!), text: text)
            }
        } else {
            options = []
        }

        questionType = DeepTutorQuizQuestionType.resolve(
            raw: rawQuestionType,
            options: options,
            questionID: id
        )

        if let answer = try container.decodeIfPresent(String.self, forKey: .correctAnswer) {
            correctAnswer = answer
        } else if let index = try container.decodeIfPresent(Int.self, forKey: .correctIndex),
                  options.indices.contains(index) {
            correctAnswer = options[index].key
        } else {
            correctAnswer = ""
        }

        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        difficulty = try container.decodeIfPresent(String.self, forKey: .difficulty)
        concentration = try container.decodeIfPresent(String.self, forKey: .concentration)
        knowledgeContext = try container.decodeIfPresent(String.self, forKey: .knowledgeContext)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .questionID)
        try container.encode(question, forKey: .question)
        try container.encode(questionType.rawValue, forKey: .questionType)
        let keyed = Dictionary(uniqueKeysWithValues: options.map { ($0.key, $0.text) })
        try container.encode(keyed, forKey: .options)
        try container.encode(correctAnswer, forKey: .correctAnswer)
        try container.encode(explanation, forKey: .explanation)
        try container.encodeIfPresent(difficulty, forKey: .difficulty)
        try container.encodeIfPresent(concentration, forKey: .concentration)
        try container.encodeIfPresent(knowledgeContext, forKey: .knowledgeContext)
    }
}

// MARK: - Answer State

nonisolated enum DeepTutorQuizReviewViewMode: String, Codable, Sendable {
    case reference
    case judgment
}

nonisolated struct DeepTutorQuizAnswerState: Codable, Equatable, Sendable, Identifiable {
    var conversationID: UUID
    var assistantMessageID: UUID
    var turnID: String?
    var questionID: String
    var questionIndex: Int
    var currentIndex: Int
    var selectedKey: String?
    var typedText: String
    var submitted: Bool
    var isCorrect: Bool?
    var submittedAt: Date?
    var aiJudgment: String?
    var reviewCollapsed: Bool

    var id: String {
        Self.stateKey(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            turnID: turnID,
            questionID: questionID
        )
    }

    static func stateKey(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        questionID: String
    ) -> String {
        let trimmedTurn = turnID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let session: String
        if let trimmedTurn, trimmedTurn.isEmpty == false {
            session = "\(conversationID.uuidString)|\(trimmedTurn)"
        } else {
            session = "\(conversationID.uuidString)|\(assistantMessageID.uuidString)|local-only"
        }
        return "\(session)|\(questionID)"
    }
}

nonisolated struct DeepTutorQuizSessionState: Codable, Equatable, Sendable {
    var conversationID: UUID
    var assistantMessageID: UUID
    var turnID: String?
    var currentIndex: Int
    var answersByQuestionID: [String: DeepTutorQuizPerQuestionAnswer]

    static func empty(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?
    ) -> DeepTutorQuizSessionState {
        DeepTutorQuizSessionState(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            turnID: turnID,
            currentIndex: 0,
            answersByQuestionID: [:]
        )
    }
}

nonisolated struct DeepTutorQuizPerQuestionAnswer: Codable, Equatable, Sendable {
    var selectedKey: String?
    var typedText: String
    var submitted: Bool
    var isCorrect: Bool?
    var submittedAt: Date?
    var aiJudgment: String?
    var reviewCollapsed: Bool
    var reviewViewMode: DeepTutorQuizReviewViewMode
    var bookmarked: Bool
    var isJudging: Bool

    static let empty = DeepTutorQuizPerQuestionAnswer(
        selectedKey: nil,
        typedText: "",
        submitted: false,
        isCorrect: nil,
        submittedAt: nil,
        aiJudgment: nil,
        reviewCollapsed: false,
        reviewViewMode: .reference,
        bookmarked: false,
        isJudging: false
    )

    enum CodingKeys: String, CodingKey {
        case selectedKey
        case typedText
        case submitted
        case isCorrect
        case submittedAt
        case aiJudgment
        case reviewCollapsed
        case reviewViewMode
        case bookmarked
        case isJudging
    }

    init(
        selectedKey: String?,
        typedText: String,
        submitted: Bool,
        isCorrect: Bool?,
        submittedAt: Date?,
        aiJudgment: String?,
        reviewCollapsed: Bool,
        reviewViewMode: DeepTutorQuizReviewViewMode = .reference,
        bookmarked: Bool = false,
        isJudging: Bool = false
    ) {
        self.selectedKey = selectedKey
        self.typedText = typedText
        self.submitted = submitted
        self.isCorrect = isCorrect
        self.submittedAt = submittedAt
        self.aiJudgment = aiJudgment
        self.reviewCollapsed = reviewCollapsed
        self.reviewViewMode = reviewViewMode
        self.bookmarked = bookmarked
        self.isJudging = isJudging
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedKey = try container.decodeIfPresent(String.self, forKey: .selectedKey)
        typedText = try container.decodeIfPresent(String.self, forKey: .typedText) ?? ""
        submitted = try container.decodeIfPresent(Bool.self, forKey: .submitted) ?? false
        isCorrect = try container.decodeIfPresent(Bool.self, forKey: .isCorrect)
        submittedAt = try container.decodeIfPresent(Date.self, forKey: .submittedAt)
        aiJudgment = try container.decodeIfPresent(String.self, forKey: .aiJudgment)
        reviewCollapsed = try container.decodeIfPresent(Bool.self, forKey: .reviewCollapsed) ?? false
        reviewViewMode = try container.decodeIfPresent(DeepTutorQuizReviewViewMode.self, forKey: .reviewViewMode) ?? .reference
        bookmarked = try container.decodeIfPresent(Bool.self, forKey: .bookmarked) ?? false
        isJudging = try container.decodeIfPresent(Bool.self, forKey: .isJudging) ?? false
    }
}
