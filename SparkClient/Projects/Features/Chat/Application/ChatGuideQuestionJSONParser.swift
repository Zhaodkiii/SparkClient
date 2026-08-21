import Foundation

private struct ChatGuideRawQuestion: Decodable {
    var id: String?
    var title: String?
    var prompt: String?
    var category: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case prompt
        case category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else if let doubleID = try? container.decode(Double.self, forKey: .id) {
            id = String(Int(doubleID))
        } else {
            id = nil
        }
        title = try? container.decode(String.self, forKey: .title)
        prompt = try? container.decode(String.self, forKey: .prompt)
        category = try? container.decode(String.self, forKey: .category)
    }
}

private struct ChatGuideWrappedQuestions: Decodable {
    var questions: [ChatGuideRawQuestion]?
}

enum ChatGuideQuestionJSONParserError: Error, Equatable {
    case emptyOutput
    case invalidJSON
    case insufficientQuestions
}

enum ChatGuideQuestionJSONParserStage: String, Sendable {
    case initial
    case repair
}

/// 解析 AI 输出的引导卡片科普问题 JSON。
enum ChatGuideQuestionJSONParser {
    static func parse(_ rawText: String) throws -> [ChatGuideQuestion] {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ChatGuideQuestionJSONParserError.emptyOutput
        }

        let jsonText = extractJSONText(from: trimmed)
        let rawQuestions = try decodeQuestions(from: jsonText)
        let normalized = normalize(rawQuestions)
        guard normalized.count >= 3 else {
            throw ChatGuideQuestionJSONParserError.insufficientQuestions
        }
        return Array(normalized.prefix(3))
    }

    static func errorCategory(for error: Error) -> String {
        switch error as? ChatGuideQuestionJSONParserError {
        case .emptyOutput:
            return "empty_output"
        case .insufficientQuestions:
            return "insufficient_questions"
        case .invalidJSON, .none:
            return "invalid_json"
        }
    }

    private static func extractJSONText(from text: String) -> String {
        guard text.contains("```") else {
            return text
        }
        var body = text
        if let fenceStart = body.range(of: "```json") ?? body.range(of: "```") {
            body = String(body[fenceStart.upperBound...])
        }
        if let fenceEnd = body.range(of: "```") {
            body = String(body[..<fenceEnd.lowerBound])
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeQuestions(from jsonText: String) throws -> [ChatGuideRawQuestion] {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ChatGuideQuestionJSONParserError.emptyOutput
        }

        let decoder = JSONDecoder()
        var candidates = [trimmed]

        if let arraySlice = extractBracketSlice(trimmed, open: "[", close: "]"), arraySlice != trimmed {
            candidates.append(arraySlice)
        }
        if let objectSlice = extractBracketSlice(trimmed, open: "{", close: "}"), objectSlice != trimmed {
            candidates.append(objectSlice)
            if objectSlice.contains("},") || objectSlice.contains("}\n,") {
                candidates.append("[\(objectSlice)]")
            }
        }

        var seen = Set<String>()
        for candidate in candidates where seen.contains(candidate) == false {
            seen.insert(candidate)
            guard let data = candidate.data(using: .utf8) else { continue }

            if let array = try? decoder.decode([ChatGuideRawQuestion].self, from: data), array.isEmpty == false {
                return array
            }
            if let wrapped = try? decoder.decode(ChatGuideWrappedQuestions.self, from: data),
               let questions = wrapped.questions,
               questions.isEmpty == false {
                return questions
            }
        }

        throw ChatGuideQuestionJSONParserError.invalidJSON
    }

    private static func extractBracketSlice(_ text: String, open: Character, close: Character) -> String? {
        guard let start = text.firstIndex(of: open),
              let end = text.lastIndex(of: close),
              start < end else {
            return nil
        }
        return String(text[start...end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ rawQuestions: [ChatGuideRawQuestion]) -> [ChatGuideQuestion] {
        var seenKeys = Set<String>()
        var result: [ChatGuideQuestion] = []

        for raw in rawQuestions {
            let title = normalizedTitle(from: raw)
            let prompt = normalizedPrompt(from: raw, title: title)
            guard title.isEmpty == false, prompt.isEmpty == false else { continue }

            let id = normalizedID(from: raw, title: title)
            let dedupeKey = "\(title.lowercased())|\(prompt.lowercased())"
            guard seenKeys.contains(dedupeKey) == false else { continue }
            seenKeys.insert(dedupeKey)

            result.append(
                ChatGuideQuestion(
                    id: id,
                    title: title,
                    prompt: prompt,
                    category: normalizedCategory(from: raw)
                )
            )
        }

        if result.count < 3 {
            for preset in ChatGuideQuestionPreset.phaseOne where result.count < 3 {
                let dedupeKey = "\(preset.title.lowercased())|\(preset.prompt.lowercased())"
                guard seenKeys.contains(dedupeKey) == false else { continue }
                seenKeys.insert(dedupeKey)
                result.append(preset)
            }
        }

        return result
    }

    private static func normalizedTitle(from raw: ChatGuideRawQuestion) -> String {
        let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty == false {
            return truncate(title, maxLength: 24)
        }
        let prompt = raw.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return truncate(prompt, maxLength: 24)
    }

    private static func normalizedPrompt(from raw: ChatGuideRawQuestion, title: String) -> String {
        let prompt = raw.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if prompt.isEmpty == false {
            return prompt
        }
        return title
    }

    private static func normalizedID(from raw: ChatGuideRawQuestion, title: String) -> String {
        let rawID = raw.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawID.isEmpty == false, isPureNumericID(rawID) == false {
            return sanitizeID(rawID)
        }
        return stableTitleBasedID(from: title)
    }

    private static func isPureNumericID(_ value: String) -> Bool {
        value.allSatisfy(\.isNumber)
    }

    private static func sanitizeID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        return slug.isEmpty ? UUID().uuidString : slug
    }

    private static func stableTitleBasedID(from title: String) -> String {
        let slug = title
            .lowercased()
            .replacingOccurrences(of: "？", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: ".", with: "")
        return slug.isEmpty ? UUID().uuidString : "guide_\(slug.prefix(32))"
    }

    private static func normalizedCategory(from raw: ChatGuideRawQuestion) -> String {
        let category = raw.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return category.isEmpty ? "popular_science" : category
    }

    private static func truncate(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else { return value }
        return String(value.prefix(maxLength))
    }
}
