import Foundation

/// DeepTutor 流式事件，对齐 Web `StreamEvent` 语义并适合本地落库。
nonisolated enum DeepTutorStreamEvent: Codable, Equatable, Sendable {
    case contentDelta(text: String, callID: String?, round: Int?)
    case reasoningDelta(text: String, callID: String?, round: Int?)
    case toolCallStarted(callID: String, toolName: String, argsSummary: String?)
    case toolProgress(callID: String, label: String, progress: Double?)
    case toolResult(callID: String, payload: DeepTutorToolResultPayload)
    case askUser(payload: DeepTutorAskUserPayload, toolCallID: String)
    case askUserResolved(toolCallID: String, answers: [DeepTutorAskUserAnswer])
    case memberSelectionRequested(reason: String, arguments: [String: String], toolCallID: String)
    case memberSelectionResolved(toolCallID: String, memberID: Int, memberName: String?)
    case quizQuestionEmitted(question: DeepTutorQuizQuestion, questionIndex: Int, turnID: String?)
    case result(metadata: [String: String], summaryJSON: String? = nil)
    case error(message: String, turnTerminal: Bool)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case callID
        case call_id
        case round
        case toolName
        case argsSummary
        case label
        case progress
        case payload
        case toolCallID
        case tool_call_id
        case answers
        case reason
        case arguments
        case memberID
        case memberName
        case metadata
        case summaryJSON
        case question
        case questionIndex
        case turnID
        case message
        case turnTerminal
    }

    private enum EventType: String, Codable {
        case contentDelta
        case reasoningDelta
        case toolCallStarted
        case toolProgress
        case toolResult
        case askUser
        case askUserResolved
        case memberSelectionRequested
        case memberSelectionResolved
        case quizQuestionEmitted
        case result
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)
        switch type {
        case .contentDelta:
            self = .contentDelta(
                text: try container.decode(String.self, forKey: .text),
                callID: try container.decodeIfPresent(String.self, forKey: .callID),
                round: try container.decodeIfPresent(Int.self, forKey: .round)
            )
        case .reasoningDelta:
            self = .reasoningDelta(
                text: try container.decode(String.self, forKey: .text),
                callID: try container.decodeIfPresent(String.self, forKey: .callID),
                round: try container.decodeIfPresent(Int.self, forKey: .round)
            )
        case .toolCallStarted:
            self = .toolCallStarted(
                callID: Self.decodeCallID(from: container, fallbackPrefix: "tool-start"),
                toolName: try container.decode(String.self, forKey: .toolName),
                argsSummary: try container.decodeIfPresent(String.self, forKey: .argsSummary)
            )
        case .toolProgress:
            self = .toolProgress(
                callID: Self.decodeCallID(from: container, fallbackPrefix: "tool-progress"),
                label: try container.decode(String.self, forKey: .label),
                progress: try container.decodeIfPresent(Double.self, forKey: .progress)
            )
        case .toolResult:
            self = .toolResult(
                callID: Self.decodeCallID(from: container, fallbackPrefix: "tool-result"),
                payload: try container.decode(DeepTutorToolResultPayload.self, forKey: .payload)
            )
        case .askUser:
            self = .askUser(
                payload: try container.decode(DeepTutorAskUserPayload.self, forKey: .payload),
                toolCallID: Self.decodeToolCallID(from: container, fallbackPrefix: "ask-user")
            )
        case .askUserResolved:
            self = .askUserResolved(
                toolCallID: Self.decodeToolCallID(from: container, fallbackPrefix: "ask-resolved"),
                answers: try container.decode([DeepTutorAskUserAnswer].self, forKey: .answers)
            )
        case .memberSelectionRequested:
            self = .memberSelectionRequested(
                reason: try container.decode(String.self, forKey: .reason),
                arguments: try container.decodeIfPresent([String: String].self, forKey: .arguments) ?? [:],
                toolCallID: Self.decodeToolCallID(from: container, fallbackPrefix: "member-selection")
            )
        case .memberSelectionResolved:
            self = .memberSelectionResolved(
                toolCallID: Self.decodeToolCallID(from: container, fallbackPrefix: "member-resolved"),
                memberID: try container.decode(Int.self, forKey: .memberID),
                memberName: try container.decodeIfPresent(String.self, forKey: .memberName)
            )
        case .quizQuestionEmitted:
            self = .quizQuestionEmitted(
                question: try container.decode(DeepTutorQuizQuestion.self, forKey: .question),
                questionIndex: try container.decode(Int.self, forKey: .questionIndex),
                turnID: try container.decodeIfPresent(String.self, forKey: .turnID)
            )
        case .result:
            self = .result(
                metadata: try container.decode([String: String].self, forKey: .metadata),
                summaryJSON: try container.decodeIfPresent(String.self, forKey: .summaryJSON)
            )
        case .error:
            self = .error(
                message: try container.decode(String.self, forKey: .message),
                turnTerminal: try container.decode(Bool.self, forKey: .turnTerminal)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .contentDelta(text, callID, round):
            try container.encode(EventType.contentDelta, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(callID, forKey: .callID)
            try container.encodeIfPresent(round, forKey: .round)
        case let .reasoningDelta(text, callID, round):
            try container.encode(EventType.reasoningDelta, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(callID, forKey: .callID)
            try container.encodeIfPresent(round, forKey: .round)
        case let .toolCallStarted(callID, toolName, argsSummary):
            try container.encode(EventType.toolCallStarted, forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(toolName, forKey: .toolName)
            try container.encodeIfPresent(argsSummary, forKey: .argsSummary)
        case let .toolProgress(callID, label, progress):
            try container.encode(EventType.toolProgress, forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(label, forKey: .label)
            try container.encodeIfPresent(progress, forKey: .progress)
        case let .toolResult(callID, payload):
            try container.encode(EventType.toolResult, forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(payload, forKey: .payload)
        case let .askUser(payload, toolCallID):
            try container.encode(EventType.askUser, forKey: .type)
            try container.encode(payload, forKey: .payload)
            try container.encode(toolCallID, forKey: .toolCallID)
        case let .askUserResolved(toolCallID, answers):
            try container.encode(EventType.askUserResolved, forKey: .type)
            try container.encode(toolCallID, forKey: .toolCallID)
            try container.encode(answers, forKey: .answers)
        case let .memberSelectionRequested(reason, arguments, toolCallID):
            try container.encode(EventType.memberSelectionRequested, forKey: .type)
            try container.encode(reason, forKey: .reason)
            try container.encode(arguments, forKey: .arguments)
            try container.encode(toolCallID, forKey: .toolCallID)
        case let .memberSelectionResolved(toolCallID, memberID, memberName):
            try container.encode(EventType.memberSelectionResolved, forKey: .type)
            try container.encode(toolCallID, forKey: .toolCallID)
            try container.encode(memberID, forKey: .memberID)
            try container.encodeIfPresent(memberName, forKey: .memberName)
        case let .quizQuestionEmitted(question, questionIndex, turnID):
            try container.encode(EventType.quizQuestionEmitted, forKey: .type)
            try container.encode(question, forKey: .question)
            try container.encode(questionIndex, forKey: .questionIndex)
            try container.encodeIfPresent(turnID, forKey: .turnID)
        case let .result(metadata, summaryJSON):
            try container.encode(EventType.result, forKey: .type)
            try container.encode(metadata, forKey: .metadata)
            try container.encodeIfPresent(summaryJSON, forKey: .summaryJSON)
        case let .error(message, turnTerminal):
            try container.encode(EventType.error, forKey: .type)
            try container.encode(message, forKey: .message)
            try container.encode(turnTerminal, forKey: .turnTerminal)
        }
    }

    private nonisolated static func decodeCallID(
        from container: KeyedDecodingContainer<CodingKeys>,
        fallbackPrefix: String
    ) -> String {
        for key in [CodingKeys.callID, .call_id, .toolCallID, .tool_call_id] {
            if let value = try? container.decode(String.self, forKey: key),
               value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return value
            }
        }
        return "legacy-\(fallbackPrefix)-\(UUID().uuidString.prefix(8))"
    }

    private nonisolated static func decodeToolCallID(
        from container: KeyedDecodingContainer<CodingKeys>,
        fallbackPrefix: String
    ) -> String {
        decodeCallID(from: container, fallbackPrefix: fallbackPrefix)
    }
}

nonisolated struct DeepTutorToolResultPayload: Codable, Equatable, Sendable {
    var kind: String
    var title: String?
    var summary: String?
    var fileURL: String?
    var mimeType: String?
    var metadata: [String: String]?
}

nonisolated struct DeepTutorAskUserPayload: Codable, Equatable, Sendable {
    var intro: String?
    var questions: [DeepTutorAskUserQuestion]
}

nonisolated struct DeepTutorAskUserQuestion: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var header: String?
    var prompt: String
    var options: [DeepTutorAskUserOption]
    var multiSelect: Bool
    var allowFreeText: Bool
    var placeholder: String?

    enum CodingKeys: String, CodingKey {
        case id
        case header
        case prompt
        case options
        case multiSelect = "multi_select"
        case allowFreeText = "allow_free_text"
        case placeholder
    }

    init(
        id: String,
        header: String?,
        prompt: String,
        options: [DeepTutorAskUserOption],
        multiSelect: Bool = false,
        allowFreeText: Bool,
        placeholder: String?
    ) {
        self.id = id
        self.header = header
        self.prompt = prompt
        self.options = options
        self.multiSelect = multiSelect
        self.allowFreeText = allowFreeText
        self.placeholder = placeholder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        prompt = try container.decode(String.self, forKey: .prompt)
        options = try container.decode([DeepTutorAskUserOption].self, forKey: .options)
        multiSelect = try container.decodeIfPresent(Bool.self, forKey: .multiSelect) ?? false
        allowFreeText = try container.decodeIfPresent(Bool.self, forKey: .allowFreeText) ?? true
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
    }
}

nonisolated struct DeepTutorAskUserOption: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var label: String
    var description: String?
}

nonisolated struct DeepTutorAskUserAnswer: Codable, Equatable, Sendable {
    var questionID: String
    var text: String

    enum CodingKeys: String, CodingKey {
        case questionID = "question_id"
        case text
    }
}
