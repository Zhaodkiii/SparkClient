import Foundation

enum DeepTutorQuizExtractor: Sendable {
    struct ExtractResult: Equatable, Sendable {
        var payload: DeepTutorQuizPayload?
        var source: DeepTutorQuizSource
        var questionCount: Int
        var failureReason: String?
    }

    nonisolated static func extract(from message: DeepTutorMessage) -> ExtractResult {
        let start = Date()
        let events = message.events
        let turnID = extractTurnID(from: events)
            ?? DeepTutorQuizAnswerStore.fallbackTurnID(assistantMessageID: message.id)

        if var resultPayload = extractFromResult(events: events, turnID: turnID) {
            if DeepTutorQuizAnswerStore.normalizedTurnID(resultPayload.turnID) == nil {
                resultPayload.turnID = turnID
            }
            logDone(
                conversationID: message.conversationID,
                assistantMessageID: message.id,
                turnID: resultPayload.turnID,
                source: resultPayload.source,
                payload: resultPayload,
                start: start
            )
            return ExtractResult(payload: resultPayload, source: resultPayload.source, questionCount: resultPayload.questions.count, failureReason: nil)
        }

        if var streamingPayload = extractFromStreaming(events: events, turnID: turnID) {
            if DeepTutorQuizAnswerStore.normalizedTurnID(streamingPayload.turnID) == nil {
                streamingPayload.turnID = turnID
            }
            logDone(
                conversationID: message.conversationID,
                assistantMessageID: message.id,
                turnID: streamingPayload.turnID,
                source: .streaming,
                payload: streamingPayload,
                start: start
            )
            return ExtractResult(payload: streamingPayload, source: .streaming, questionCount: streamingPayload.questions.count, failureReason: nil)
        }

        reportExtractionFailure(
            message: message,
            turnID: turnID,
            reason: "no_quiz_data",
            start: start
        )
        return ExtractResult(payload: nil, source: .streaming, questionCount: 0, failureReason: "no_quiz_data")
    }

    nonisolated private static func reportExtractionFailure(
        message: DeepTutorMessage,
        turnID: String?,
        reason: String,
        start: Date
    ) {
        if message.status == .streaming {
            DeepTutorChatLog.quizExtractSkippedNoNewData(
                conversationID: message.conversationID,
                assistantMessageID: message.id,
                phase: message.status.rawValue,
                reason: reason
            )
        } else {
            DeepTutorChatLog.quizExtractFailed(
                conversationID: message.conversationID,
                assistantMessageID: message.id,
                turnID: turnID,
                reason: reason,
                durationMs: Date().timeIntervalSince(start) * 1000
            )
        }
    }

    nonisolated static func extractTurnID(from events: [DeepTutorStreamEvent]) -> String? {
        for event in events.reversed() {
            if case let .result(metadata, _) = event,
               let turnID = metadata["turn_id"] ?? metadata["turnID"],
               turnID.isEmpty == false {
                return turnID
            }
        }
        for event in events {
            if case let .quizQuestionEmitted(_, _, turnID) = event,
               let turnID,
               turnID.isEmpty == false {
                return turnID
            }
        }
        return nil
    }

    nonisolated private static func extractFromStreaming(
        events: [DeepTutorStreamEvent],
        turnID: String?
    ) -> DeepTutorQuizPayload? {
        var byKey: [String: (index: Int, question: DeepTutorQuizQuestion)] = [:]

        for event in events {
            guard case let .quizQuestionEmitted(question, questionIndex, eventTurnID) = event else { continue }
            let key = question.id.isEmpty ? "idx-\(questionIndex)" : question.id
            byKey[key] = (questionIndex, question)
            DeepTutorChatLog.quizExtractStreamingQuestion(
                turnID: eventTurnID ?? turnID,
                questionID: question.id,
                questionIndex: questionIndex,
                questionType: question.questionType.rawValue
            )
        }

        let questions = byKey.values
            .sorted { $0.index < $1.index }
            .map(\.question)

        guard questions.isEmpty == false else { return nil }
        return DeepTutorQuizPayload(
            title: "Quick Check",
            turnID: turnID,
            questions: questions,
            source: .streaming
        )
    }

    nonisolated private static func extractFromResult(
        events: [DeepTutorStreamEvent],
        turnID: String?
    ) -> DeepTutorQuizPayload? {
        let resultEvents: [(metadata: [String: String], summaryJSON: String?)] = events.compactMap { event in
            guard case let .result(metadata, summaryJSON) = event else { return nil }
            return (metadata, summaryJSON)
        }
        guard resultEvents.isEmpty == false else { return nil }

        for resultEvent in resultEvents.reversed() {
            if let payload = payloadFromResultEvent(resultEvent, turnID: turnID) {
                return payload
            }
        }
        return nil
    }

    nonisolated private static func payloadFromResultEvent(
        _ resultEvent: (metadata: [String: String], summaryJSON: String?),
        turnID: String?
    ) -> DeepTutorQuizPayload? {
        let metadata = resultEvent.metadata
        guard metadata["parse_failed"] != "true" else { return nil }

        let jsonObject: [String: Any]
        if let summaryJSON = resultEvent.summaryJSON,
           let data = summaryJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            jsonObject = parsed
        } else if let summaryString = metadata["summary_json"],
                  let data = summaryString.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            jsonObject = parsed
        } else {
            return nil
        }

        guard let results = jsonObject["results"] as? [[String: Any]], results.isEmpty == false else {
            return nil
        }

        var questions: [DeepTutorQuizQuestion] = []
        for (index, item) in results.enumerated() {
            let qaObject = (item["qa_pair"] as? [String: Any]) ?? item
            guard let question = parseQuestion(from: qaObject, fallbackIndex: index) else { continue }
            questions.append(question)
            DeepTutorChatLog.quizExtractResultQuestion(
                turnID: turnID,
                questionID: question.id,
                questionIndex: index,
                questionType: question.questionType.rawValue
            )
        }

        guard questions.isEmpty == false else { return nil }
        let source: DeepTutorQuizSource
        if metadata["source"] == "quiz_content_parser" {
            source = .contentParser
        } else {
            source = .result
        }
        return DeepTutorQuizPayload(
            title: "Quick Check",
            turnID: turnID ?? metadata["turn_id"] ?? metadata["turnID"],
            questions: questions,
            source: source
        )
    }

    nonisolated static func parseQuestion(from object: [String: Any], fallbackIndex: Int) -> DeepTutorQuizQuestion? {
        guard let questionText = object["question"] as? String,
              questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let parsed = try? DeepTutorMessageCodec.decoder.decode(DeepTutorQuizQuestion.self, from: data) else {
            return nil
        }

        let questionID = parsed.id.isEmpty ? "q_\(fallbackIndex + 1)" : parsed.id
        let resolvedType = DeepTutorQuizQuestionType.resolve(
            raw: object["question_type"] as? String,
            options: parsed.options,
            questionID: questionID
        )

        return DeepTutorQuizQuestion(
            id: questionID,
            question: parsed.question,
            questionType: resolvedType,
            options: parsed.options,
            correctAnswer: parsed.correctAnswer,
            explanation: parsed.explanation,
            difficulty: parsed.difficulty,
            concentration: parsed.concentration,
            knowledgeContext: parsed.knowledgeContext
        )
    }

    nonisolated private static func logDone(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        source: DeepTutorQuizSource,
        payload: DeepTutorQuizPayload,
        start: Date
    ) {
        DeepTutorChatLog.quizExtractDone(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            turnID: turnID,
            source: source.rawValue,
            questionCount: payload.questions.count,
            questionIDs: payload.questions.map(\.id),
            questionTypes: payload.questions.map(\.questionType.rawValue),
            hasExplanation: payload.questions.contains { $0.explanation.isEmpty == false },
            durationMs: Date().timeIntervalSince(start) * 1000
        )
    }
}
