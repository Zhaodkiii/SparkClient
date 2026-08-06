import Foundation

/// Parses quiz JSON from chat-completion prose and converts it into `.result(summaryJSON:)`
/// events consumed by `DeepTutorQuizExtractor`.
enum DeepTutorQuizContentParser: Sendable {
    enum DetectedPattern: String, Sendable {
        case quizJsonFence = "quiz_json_fence"
        case jsonFence = "json_fence"
        case bareResultsObject = "bare_results_object"
        case bareResultsArray = "bare_results_array"
        case bareQAPairObject = "bare_qa_pair_object"
        case recoveredObject = "recovered_object"
        case repairedBraceStructure = "repaired_brace_structure"
        case repairedPseudoJSON = "repaired_pseudo_json"
        case none = "none"
    }

    struct ParseOutcome: Equatable, Sendable {
        var strippedContent: String
        var summaryJSON: String?
        var foundStructuredPayload: Bool
        var parseFailed: Bool
        var pattern: DetectedPattern
        var parseFailureReason: String?
        var repairStrategy: String?
    }

    nonisolated static let parseFailureUserMessage = "问答结构解析失败，请重试生成题目。"

    nonisolated static func parse(content: String) -> ParseOutcome {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return ParseOutcome(
                strippedContent: content,
                summaryJSON: nil,
                foundStructuredPayload: false,
                parseFailed: false,
                pattern: .none,
                parseFailureReason: nil,
                repairStrategy: nil
            )
        }

        if let fenced = extractFencedBlock(in: trimmed, opener: "```quiz_json") {
            return finalize(
                content: trimmed,
                jsonBody: fenced.jsonBody,
                removalRange: fenced.removalRange,
                pattern: .quizJsonFence
            )
        }

        if let fenced = extractFencedBlock(in: trimmed, opener: "```json") {
            let outcome = finalize(
                content: trimmed,
                jsonBody: fenced.jsonBody,
                removalRange: fenced.removalRange,
                pattern: .jsonFence
            )
            if outcome.summaryJSON != nil || outcome.parseFailed {
                return outcome
            }
        }

        if let object = extractFirstJSONObject(in: trimmed, requiringKey: "results") {
            return finalize(
                content: trimmed,
                jsonBody: object.jsonBody,
                removalRange: object.removalRange,
                pattern: .bareResultsObject
            )
        }

        if let array = extractFirstJSONArray(in: trimmed) {
            let wrapped = "{\"results\":\(array.jsonBody)}"
            if validatedSummaryJSON(from: wrapped) != nil {
                return finalize(
                    content: trimmed,
                    jsonBody: wrapped,
                    removalRange: array.removalRange,
                    pattern: .bareResultsArray
                )
            }
        }

        if let qaPair = extractFirstJSONObject(in: trimmed, requiringKey: "question") {
            let wrapped = "{\"results\":[{\"qa_pair\":\(qaPair.jsonBody)}]}"
            if validatedSummaryJSON(from: wrapped) != nil {
                return finalize(
                    content: trimmed,
                    jsonBody: wrapped,
                    removalRange: qaPair.removalRange,
                    pattern: .bareQAPairObject
                )
            }
        }

        if looksLikeQuizJSON(trimmed) {
            return ParseOutcome(
                strippedContent: introBeforeQuizPayload(trimmed) ?? parseFailureUserMessage,
                summaryJSON: nil,
                foundStructuredPayload: true,
                parseFailed: true,
                pattern: .recoveredObject,
                parseFailureReason: classifyParseFailure(in: trimmed),
                repairStrategy: nil
            )
        }

        return ParseOutcome(
            strippedContent: content,
            summaryJSON: nil,
            foundStructuredPayload: false,
            parseFailed: false,
            pattern: .none,
            parseFailureReason: nil,
            repairStrategy: nil
        )
    }

    nonisolated static func apply(to message: DeepTutorMessage) -> DeepTutorMessage {
        guard message.capability == .deepQuestion else { return message }

        DeepTutorChatLog.quizContentParserStart(
            conversationID: message.conversationID,
            assistantMessageID: message.id,
            capability: message.capability.rawValue,
            contentLength: message.content.count
        )

        let outcome = parse(content: message.content)
        if outcome.foundStructuredPayload == false {
            return message
        }

        DeepTutorChatLog.quizContentParserDetected(
            conversationID: message.conversationID,
            assistantMessageID: message.id,
            pattern: outcome.pattern.rawValue,
            contentLength: message.content.count
        )

        guard let summaryJSON = outcome.summaryJSON else {
            let failureReason = outcome.parseFailureReason ?? "json_parse_failed"
            DeepTutorChatLog.quizContentParserFailed(
                conversationID: message.conversationID,
                assistantMessageID: message.id,
                reason: failureReason,
                pattern: outcome.pattern.rawValue,
                rawPreview: String(message.content.prefix(240))
            )
            DeepTutorChatLog.quizContentParserRawSuppressed(
                conversationID: message.conversationID,
                assistantMessageID: message.id,
                pattern: outcome.pattern.rawValue
            )
            var events = message.events
            events.removeAll { event in
                guard case let .result(metadata, _) = event else { return false }
                return metadata["source"] == "quiz_content_parser"
            }
            events.append(
                .result(
                    metadata: quizParserResultMetadata(
                        messageID: message.id,
                        extras: [
                            "parse_failed": "true",
                            "parse_failure_reason": failureReason,
                            "pattern": outcome.pattern.rawValue,
                        ]
                    ),
                    summaryJSON: nil
                )
            )
            return message.replacing(content: outcome.strippedContent, events: events)
        }

        var events = message.events
        events.removeAll { event in
            guard case let .result(metadata, _) = event else { return false }
            return metadata["source"] == "quiz_content_parser"
        }
        events.append(
            .result(
                metadata: quizParserResultMetadata(
                    messageID: message.id,
                    extras: [:]
                ),
                summaryJSON: summaryJSON
            )
        )

        DeepTutorChatLog.quizContentParserStripped(
            conversationID: message.conversationID,
            assistantMessageID: message.id,
            questionCount: questionCount(in: summaryJSON),
            strippedLength: outcome.strippedContent.count,
            pattern: outcome.pattern.rawValue
        )
        if let repairStrategy = outcome.repairStrategy {
            DeepTutorChatLog.quizContentParserRepairDone(
                conversationID: message.conversationID,
                assistantMessageID: message.id,
                strategy: repairStrategy,
                questionCount: questionCount(in: summaryJSON)
            )
        }

        return message.replacing(content: outcome.strippedContent, events: events)
    }

    /// Streaming-safe visible content: keep intro prose, hide in-progress quiz JSON.
    nonisolated static func visibleStreamingContent(from content: String, capability: DeepTutorCapability) -> String {
        guard capability == .deepQuestion else { return content }
        guard looksLikeQuizJSON(content) || introBeforeQuizPayload(content) != nil else {
            return content
        }
        return introBeforeQuizPayload(content) ?? ""
    }

    /// Apply parser during streaming when enough structure is available.
    nonisolated static func applyDuringStreaming(to message: DeepTutorMessage) -> DeepTutorMessage {
        guard message.capability == .deepQuestion else { return message }

        let visible = visibleStreamingContent(from: message.content, capability: message.capability)
        let interim = message.replacing(content: visible)
        let parsed = parse(content: message.content)
        guard let summaryJSON = parsed.summaryJSON else {
            return interim
        }

        var events = message.events
        events.removeAll { event in
            guard case let .result(metadata, _) = event else { return false }
            return metadata["source"] == "quiz_content_parser"
        }
        events.append(
            .result(
                metadata: quizParserResultMetadata(
                    messageID: message.id,
                    extras: [:]
                ),
                summaryJSON: summaryJSON
            )
        )
        return interim.replacing(content: parsed.strippedContent, events: events)
    }

    nonisolated static func looksLikeQuizJSON(_ content: String) -> Bool {
        let normalized = content.lowercased()
        let markers = [
            "\"question_type\"",
            "\"correct_answer\"",
            "\"qa_pair\"",
            "\"results\"",
            "```quiz_json",
            "```json",
        ]
        let markerHits = markers.filter { normalized.contains($0) }.count
        if markerHits >= 2 { return true }
        if normalized.contains("\"question\"") && normalized.contains("\"options\"") { return true }
        if normalized.contains("\"question\"") && normalized.contains("\"question_type\"") { return true }
        return false
    }

    nonisolated static func introBeforeQuizPayload(_ content: String) -> String? {
        let markers = [
            "```quiz_json",
            "```json",
            "{\"results\"",
            "[{\"qa_pair\"",
            "\"question_type\"",
            "\"question_id\"",
            "\"question\"",
        ]
        var earliest: String.Index?
        for marker in markers {
            guard let range = content.range(of: marker) else { continue }
            if earliest == nil || range.lowerBound < earliest! {
                earliest = range.lowerBound
            }
        }
        guard let start = earliest else { return nil }
        let intro = content[..<start].trimmingCharacters(in: .whitespacesAndNewlines)
        return intro.isEmpty ? nil : String(intro)
    }

    nonisolated static func parseFailureReason(in events: [DeepTutorStreamEvent]) -> String? {
        for event in events.reversed() {
            guard case let .result(metadata, _) = event,
                  metadata["source"] == "quiz_content_parser",
                  metadata["parse_failed"] == "true" else {
                continue
            }
            return metadata["parse_failure_reason"]
        }
        return nil
    }

    nonisolated static func hasQuizJsonInContent(_ content: String) -> Bool {
        content.lowercased().contains("```quiz_json") || looksLikeQuizJSON(content)
    }

    nonisolated private static func quizParserResultMetadata(
        messageID: UUID,
        extras: [String: String]
    ) -> [String: String] {
        var metadata: [String: String] = [
            "source": "quiz_content_parser",
            "turn_id": DeepTutorQuizAnswerStore.fallbackTurnID(assistantMessageID: messageID),
        ]
        for (key, value) in extras {
            metadata[key] = value
        }
        return metadata
    }

    nonisolated static func stripQuizLeak(from text: String) -> String? {
        guard looksLikeQuizJSON(text) else { return nil }
        return introBeforeQuizPayload(text)
    }

    // MARK: - Private

    private struct ExtractedSegment {
        let jsonBody: String
        let removalRange: Range<String.Index>
    }

    nonisolated private static func finalize(
        content: String,
        jsonBody: String,
        removalRange: Range<String.Index>,
        pattern: DetectedPattern
    ) -> ParseOutcome {
        let stripped = mergeIntroAndTail(content: content, removalRange: removalRange)
        if let summaryJSON = validatedSummaryJSON(from: jsonBody) {
            return ParseOutcome(
                strippedContent: stripped,
                summaryJSON: summaryJSON,
                foundStructuredPayload: true,
                parseFailed: false,
                pattern: pattern,
                parseFailureReason: nil,
                repairStrategy: nil
            )
        }

        if let repaired = attemptDeterministicRepair(
            jsonBody: jsonBody,
            conversationID: nil,
            assistantMessageID: nil
        ) {
            let repairedPattern: DetectedPattern
            switch repaired.strategy {
            case "brace_structure":
                repairedPattern = .repairedBraceStructure
            case "pseudo_json_rebuild":
                repairedPattern = .repairedPseudoJSON
            default:
                repairedPattern = pattern
            }
            return ParseOutcome(
                strippedContent: stripped,
                summaryJSON: repaired.summaryJSON,
                foundStructuredPayload: true,
                parseFailed: false,
                pattern: repairedPattern,
                parseFailureReason: nil,
                repairStrategy: repaired.strategy
            )
        }

        return ParseOutcome(
            strippedContent: stripped.isEmpty ? parseFailureUserMessage : stripped,
            summaryJSON: nil,
            foundStructuredPayload: true,
            parseFailed: true,
            pattern: pattern,
            parseFailureReason: classifyParseFailure(in: jsonBody),
            repairStrategy: nil
        )
    }

    nonisolated private static func mergeIntroAndTail(
        content: String,
        removalRange: Range<String.Index>
    ) -> String {
        let intro = content[..<removalRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = content[removalRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return [intro, tail]
            .filter { $0.isEmpty == false }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func extractFencedBlock(
        in content: String,
        opener: String
    ) -> ExtractedSegment? {
        guard let openerRange = content.range(of: opener) else { return nil }
        let bodyStart = openerRange.upperBound
        let afterOpener = content[bodyStart...]
        let jsonStart: String.Index
        if let newline = afterOpener.firstIndex(of: "\n") {
            jsonStart = content.index(after: newline)
        } else {
            jsonStart = bodyStart
        }

        if let closerRange = content[jsonStart...].range(of: "\n```") {
            let jsonEnd = closerRange.lowerBound
            guard jsonStart < jsonEnd else { return nil }
            return ExtractedSegment(
                jsonBody: String(content[jsonStart..<jsonEnd]),
                removalRange: openerRange.lowerBound..<closerRange.upperBound
            )
        }

        let jsonBody = String(content[jsonStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard jsonBody.isEmpty == false else { return nil }
        return ExtractedSegment(
            jsonBody: jsonBody,
            removalRange: openerRange.lowerBound..<content.endIndex
        )
    }

    nonisolated private static func extractFirstJSONObject(
        in content: String,
        requiringKey key: String
    ) -> ExtractedSegment? {
        var searchStart = content.startIndex
        while searchStart < content.endIndex,
              let open = content[searchStart...].firstIndex(of: "{") {
            guard let close = matchingClosingBrace(in: content, openingAt: open) else { break }
            let candidate = String(content[open...close])
            if candidate.contains("\"\(key)\""),
               validatedSummaryJSON(from: normalizedSummaryJSON(from: candidate) ?? candidate) != nil
                || key == "question" {
                if key == "question" {
                    let wrapped = "{\"results\":[{\"qa_pair\":\(candidate)}]}"
                    if validatedSummaryJSON(from: wrapped) != nil {
                        return ExtractedSegment(jsonBody: wrapped, removalRange: open..<content.index(after: close))
                    }
                } else if let normalized = normalizedSummaryJSON(from: candidate) {
                    return ExtractedSegment(jsonBody: normalized, removalRange: open..<content.index(after: close))
                }
            }
            searchStart = content.index(after: close)
        }
        return nil
    }

    nonisolated private static func extractFirstJSONArray(in content: String) -> ExtractedSegment? {
        guard let open = content.firstIndex(of: "["),
              let close = matchingClosingBracket(in: content, openingAt: open) else {
            return nil
        }
        let candidate = String(content[open...close])
        guard candidate.contains("qa_pair") || candidate.contains("question_type") else { return nil }
        return ExtractedSegment(jsonBody: candidate, removalRange: open..<content.index(after: close))
    }

    nonisolated private static func normalizedSummaryJSON(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        if let dict = object as? [String: Any], dict["results"] != nil {
            return raw
        }
        if let array = object as? [[String: Any]], array.isEmpty == false {
            let wrapped: [String: Any] = ["results": array]
            guard let data = try? JSONSerialization.data(withJSONObject: wrapped),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }
        if let dict = object as? [String: Any], dict["question"] != nil {
            let wrapped: [String: Any] = ["results": [["qa_pair": dict]]]
            guard let data = try? JSONSerialization.data(withJSONObject: wrapped),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }
        return nil
    }

    nonisolated private static func validatedSummaryJSON(from rawJSON: String) -> String? {
        let trimmed = rawJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let normalized = normalizedSummaryJSON(from: trimmed),
              let data = normalized.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]],
              results.isEmpty == false else {
            return nil
        }

        let hasQuestion = results.contains { item in
            let qa = (item["qa_pair"] as? [String: Any]) ?? item
            guard let question = qa["question"] as? String else { return false }
            return question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        guard hasQuestion else { return nil }
        return normalized
    }

    nonisolated private static func questionCount(in summaryJSON: String) -> Int {
        guard let data = summaryJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]] else {
            return 0
        }
        return results.count
    }

    nonisolated private static func matchingClosingBrace(in content: String, openingAt open: String.Index) -> String.Index? {
        guard content[open] == "{" else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = open
        while index < content.endIndex {
            let char = content[index]
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else {
                if char == "\"" {
                    inString = true
                } else if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }
            index = content.index(after: index)
        }
        return nil
    }

    nonisolated private static func matchingClosingBracket(in content: String, openingAt open: String.Index) -> String.Index? {
        guard content[open] == "[" else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = open
        while index < content.endIndex {
            let char = content[index]
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else {
                if char == "\"" {
                    inString = true
                } else if char == "[" {
                    depth += 1
                } else if char == "]" {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }
            index = content.index(after: index)
        }
        return nil
    }

    // MARK: - Deterministic repair

    private struct RepairResult {
        let summaryJSON: String
        let strategy: String
    }

    nonisolated private static func attemptDeterministicRepair(
        jsonBody: String,
        conversationID: UUID?,
        assistantMessageID: UUID?
    ) -> RepairResult? {
        if let repaired = repairBraceStructure(jsonBody),
           let summaryJSON = validatedSummaryJSON(from: repaired) {
            logRepairDone(
                conversationID: conversationID,
                assistantMessageID: assistantMessageID,
                strategy: "brace_structure",
                questionCount: questionCount(in: summaryJSON)
            )
            return RepairResult(summaryJSON: summaryJSON, strategy: "brace_structure")
        }

        if let rebuilt = rebuildSummaryFromPseudoJSON(jsonBody),
           let summaryJSON = validatedSummaryJSON(from: rebuilt) {
            logRepairDone(
                conversationID: conversationID,
                assistantMessageID: assistantMessageID,
                strategy: "pseudo_json_rebuild",
                questionCount: questionCount(in: summaryJSON)
            )
            return RepairResult(summaryJSON: summaryJSON, strategy: "pseudo_json_rebuild")
        }

        return nil
    }

    nonisolated private static func repairBraceStructure(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("```") {
            text = String(text.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard text.isEmpty == false else { return nil }

        if text.hasPrefix("{") == false {
            text = "{\(text)"
        }
        if text.hasSuffix("}") == false {
            text = "\(text)}"
        }

        if text.contains("\"results\""),
           text.contains("\"results\":[") == false,
           text.contains("\"results\": [") == false {
            text = text.replacingOccurrences(
                of: #""results"\s*:\s*\n\s*"qa_pair"\s*:"#,
                with: "\"results\":[{\"qa_pair\":",
                options: .regularExpression
            )
            text = text.replacingOccurrences(
                of: #""results"\s*:\s*\n\s*\{\s*"qa_pair"\s*:"#,
                with: "\"results\":[{\"qa_pair\":",
                options: .regularExpression
            )
            if text.contains("\"results\":[") == false {
                text = text.replacingOccurrences(
                    of: #""results"\s*:\s*\n"#,
                    with: "\"results\":[\n",
                    options: .regularExpression
                )
            }
        }

        text = text.replacingOccurrences(
            of: #""qa_pair"\s*:\s*\n\s*"question"#,
            with: "\"qa_pair\":{\n        \"question",
            options: .regularExpression
        )

        text = text.replacingOccurrences(
            of: #""options"\s*:\s*\n\s*"([A-D])""#,
            with: "\"options\":{\n          \"\\(1)\"",
            options: .regularExpression
        )

        text = text.replacingOccurrences(
            of: #"(\n\s*\"D\"\s*:\s*\"(?:\\.|[^\"\\])*\")\s*,\s*\n\s*\"correct_answer\""#,
            with: "$1\n        },\n        \"correct_answer\"",
            options: .regularExpression
        )

        text = text.replacingOccurrences(
            of: #"(\n\s*\"concentration\"\s*:\s*\"(?:\\.|[^\"\\])*\")\s*\n\s*,\s*\n\s*\"qa_pair\""#,
            with: "$1\n      }},\n      {\"qa_pair\"",
            options: .regularExpression
        )

        if text.contains("\"results\":[") && text.contains("]}") == false {
            if let lastBrace = text.lastIndex(of: "}") {
                text.insert(contentsOf: "]", at: lastBrace)
            }
        }

        return text
    }

    nonisolated private static func rebuildSummaryFromPseudoJSON(_ raw: String) -> String? {
        let segments = splitQuestionSegments(raw)
        guard segments.isEmpty == false else { return nil }

        var results: [[String: Any]] = []
        for segment in segments {
            guard let qaPair = parseQAPairSegment(segment) else { continue }
            results.append(["qa_pair": qaPair])
        }
        guard results.isEmpty == false else { return nil }

        let wrapper: [String: Any] = ["results": results]
        guard let data = try? JSONSerialization.data(withJSONObject: wrapper),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    nonisolated private static func splitQuestionSegments(_ raw: String) -> [String] {
        let pattern = #""question_id"\s*:\s*"(q_\d+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(raw.startIndex..., in: raw)
        let matches = regex.matches(in: raw, range: nsRange)
        guard matches.isEmpty == false else { return [] }

        var segments: [String] = []
        for (index, match) in matches.enumerated() {
            guard let range = Range(match.range, in: raw) else { continue }
            let start = range.lowerBound
            let end: String.Index
            if index + 1 < matches.count, let nextRange = Range(matches[index + 1].range, in: raw) {
                end = nextRange.lowerBound
            } else {
                end = raw.endIndex
            }
            segments.append(String(raw[start..<end]))
        }
        return segments
    }

    nonisolated private static func parseQAPairSegment(_ segment: String) -> [String: Any]? {
        guard let question = extractQuotedField("question", in: segment),
              question.isEmpty == false else {
            return nil
        }

        var qaPair: [String: Any] = [
            "question": question,
        ]

        if let questionID = extractQuotedField("question_id", in: segment) {
            qaPair["question_id"] = questionID
        }
        if let questionType = extractQuotedField("question_type", in: segment) {
            qaPair["question_type"] = questionType
        }
        if let correctAnswer = extractQuotedField("correct_answer", in: segment) {
            qaPair["correct_answer"] = correctAnswer
        }
        if let explanation = extractQuotedField("explanation", in: segment) {
            qaPair["explanation"] = explanation
        }
        if let difficulty = extractQuotedField("difficulty", in: segment) {
            qaPair["difficulty"] = difficulty
        }
        if let concentration = extractQuotedField("concentration", in: segment) {
            qaPair["concentration"] = concentration
        }
        if let options = extractOptions(in: segment), options.isEmpty == false {
            qaPair["options"] = options
        }

        return qaPair
    }

    nonisolated private static func extractQuotedField(_ key: String, in text: String) -> String? {
        let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    nonisolated private static func extractOptions(in segment: String) -> [String: String]? {
        guard let optionsMarker = segment.range(of: "\"options\"") else { return nil }
        let afterOptions = segment[optionsMarker.upperBound...]
        let optionsText: Substring
        if let correctAnswerRange = afterOptions.range(of: "\"correct_answer\"") {
            optionsText = afterOptions[..<correctAnswerRange.lowerBound]
        } else {
            optionsText = afterOptions
        }

        let pattern = #""([A-D])"\s*:\s*"((?:\\.|[^"\\])*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        var options: [String: String] = [:]
        let nsRange = NSRange(optionsText.startIndex..., in: optionsText)
        for match in regex.matches(in: String(optionsText), range: nsRange) {
            guard let keyRange = Range(match.range(at: 1), in: optionsText),
                  let valueRange = Range(match.range(at: 2), in: optionsText) else {
                continue
            }
            options[String(optionsText[keyRange])] = String(optionsText[valueRange])
        }
        return options.isEmpty ? nil : options
    }

    nonisolated private static func classifyParseFailure(in raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("{") == false {
            return "missing_object_start"
        }
        if normalized.contains("\"results\""),
           normalized.contains("\"results\":[") == false,
           normalized.contains("\"results\": [") == false {
            return "missing_results_array"
        }
        if normalized.contains("\"qa_pair\""),
           normalized.contains("\"qa_pair\":{") == false,
           normalized.contains("\"qa_pair\": {") == false {
            return "missing_qa_pair_object"
        }
        if normalized.contains("\"options\""),
           normalized.contains("\"options\":{") == false,
           normalized.contains("\"options\": {") == false {
            return "missing_options_object"
        }
        return "json_validation_failed"
    }

    nonisolated private static func logRepairDone(
        conversationID: UUID?,
        assistantMessageID: UUID?,
        strategy: String,
        questionCount: Int
    ) {
        guard let conversationID, let assistantMessageID else { return }
        DeepTutorChatLog.quizContentParserRepairDone(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            strategy: strategy,
            questionCount: questionCount
        )
    }
}
