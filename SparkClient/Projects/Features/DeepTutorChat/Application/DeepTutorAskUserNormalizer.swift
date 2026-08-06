import Foundation

enum DeepTutorAskUserNormalizer: Sendable {
    nonisolated static func isAskUserTool(_ toolName: String?) -> Bool {
        guard let normalized = toolName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            normalized.isEmpty == false else {
            return false
        }
        return normalized == "ask_user" || normalized == SparkToolName.askUserQuestion.rawValue
    }

    nonisolated static func canonicalToolName(for toolName: String) -> String {
        isAskUserTool(toolName) ? "ask_user" : toolName
    }

    nonisolated static func payload(fromJSONObject object: Any) -> DeepTutorAskUserPayload? {
        guard let dictionary = object as? [String: Any] else { return nil }
        if let questionsRaw = dictionary["questions"] as? [Any] {
            let questions = questionsRaw.enumerated().compactMap { index, item in
                question(from: item, index: index)
            }
            guard questions.isEmpty == false else { return nil }
            return DeepTutorAskUserPayload(
                intro: string(dictionary["intro"]) ?? string(dictionary["question"]),
                questions: questions
            )
        }
        return singleQuestionPayload(fromJSONObject: dictionary)
    }

    nonisolated static func validated(_ payload: DeepTutorAskUserPayload) -> DeepTutorAskUserPayload? {
        let questions = payload.questions.compactMap { question -> DeepTutorAskUserQuestion? in
            guard isValidPrompt(question.prompt) else { return nil }
            return question
        }
        guard questions.isEmpty == false else { return nil }
        return DeepTutorAskUserPayload(intro: payload.intro, questions: questions)
    }

    nonisolated static func isValidPrompt(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        if trimmed == "{" || trimmed == "{\"" || trimmed == "[" {
            return false
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if trimmed.contains("\"questions\"") || trimmed.contains("\"question\"") {
                return payload(fromJSONString: trimmed) != nil
            }
            return false
        }
        if trimmed.count <= 2, trimmed.allSatisfy({ "{[\"]}".contains($0) }) {
            return false
        }
        return true
    }

    nonisolated static func payload(from arguments: [String: String]) -> DeepTutorAskUserPayload? {
        if let askUserJSON = arguments["ask_user"],
           let payload = payload(fromJSONString: askUserJSON) {
            return payload
        }
        if let toolMetadataJSON = arguments["tool_metadata"],
           let payload = payloadFromToolMetadata(toolMetadataJSON) {
            return payload
        }
        if let questionsJSON = arguments["questions"],
           let questions = questions(fromJSONString: questionsJSON),
           questions.isEmpty == false {
            return DeepTutorAskUserPayload(intro: intro(from: arguments), questions: questions)
        }
        return singleQuestionPayload(from: arguments)
    }

    nonisolated static func payload(fromToolResult toolResult: DeepTutorToolResultPayload) -> DeepTutorAskUserPayload? {
        guard isAskUserTool(toolResult.kind) else { return nil }
        if let metadata = toolResult.metadata,
           let normalized = self.payload(from: metadata) {
            return normalized
        }
        if let summary = toolResult.summary,
           let parsed = self.payload(fromJSONString: summary) {
            return parsed
        }
        return nil
    }

    nonisolated static func flattenedAnswerText(_ answers: [DeepTutorAskUserAnswer]) -> String {
        answers
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " | ")
    }

    private nonisolated static func payloadFromToolMetadata(_ raw: String) -> DeepTutorAskUserPayload? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let askUser = object["ask_user"] else {
            return nil
        }
        return payload(fromJSONObject: askUser)
    }

    private nonisolated static func payload(fromJSONString raw: String) -> DeepTutorAskUserPayload? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return payload(fromJSONObject: object)
    }

    private nonisolated static func questions(fromJSONString raw: String) -> [DeepTutorAskUserQuestion]? {
        guard let data = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return nil
        }
        return array.enumerated().compactMap { index, item in
            question(from: item, index: index)
        }
    }

    private nonisolated static func question(from item: Any, index: Int) -> DeepTutorAskUserQuestion? {
        guard let dictionary = item as? [String: Any] else { return nil }
        let prompt = string(dictionary["prompt"]) ?? string(dictionary["question"]) ?? string(dictionary["title"])
        guard let prompt, isValidPrompt(prompt) else { return nil }
        let optionsRaw = dictionary["options"] as? [Any] ?? []
        let options = optionsRaw.enumerated().compactMap { optionIndex, item in
            option(from: item, questionIndex: index, optionIndex: optionIndex)
        }
        return DeepTutorAskUserQuestion(
            id: string(dictionary["id"]) ?? "q\(index + 1)",
            header: string(dictionary["header"]),
            prompt: prompt,
            options: options,
            multiSelect: bool(dictionary["multi_select"]) ?? bool(dictionary["multiSelect"]) ?? (selectionMode(dictionary) == "multiple"),
            allowFreeText: bool(dictionary["allow_free_text"]) ?? bool(dictionary["allows_other"]) ?? bool(dictionary["allowFreeText"]) ?? true,
            placeholder: string(dictionary["placeholder"])
        )
    }

    private nonisolated static func option(from item: Any, questionIndex: Int, optionIndex: Int) -> DeepTutorAskUserOption? {
        if let dictionary = item as? [String: Any] {
            let label = string(dictionary["label"]) ?? string(dictionary["text"]) ?? string(dictionary["title"])
            guard let label, label.isEmpty == false else { return nil }
            return DeepTutorAskUserOption(
                id: string(dictionary["id"]) ?? "opt-\(questionIndex + 1)-\(optionIndex + 1)",
                label: label,
                description: string(dictionary["description"])
            )
        }
        guard let label = string(item), label.isEmpty == false else { return nil }
        return DeepTutorAskUserOption(
            id: "opt-\(questionIndex + 1)-\(optionIndex + 1)",
            label: label,
            description: nil
        )
    }

    private nonisolated static func singleQuestionPayload(from arguments: [String: String]) -> DeepTutorAskUserPayload? {
        let question = (arguments["question"] ?? arguments["query"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidPrompt(question) else { return nil }
        let options = parseOptions(arguments["options"]).enumerated().map { index, label in
            DeepTutorAskUserOption(id: "opt-\(index + 1)", label: label, description: nil)
        }
        return DeepTutorAskUserPayload(
            intro: intro(from: arguments),
            questions: [
                DeepTutorAskUserQuestion(
                    id: "q1",
                    header: nil,
                    prompt: question,
                    options: options,
                    multiSelect: arguments["selection_mode"] == "multiple",
                    allowFreeText: parseBool(arguments["allow_free_text"]) ?? parseBool(arguments["allows_other"]) ?? true,
                    placeholder: arguments["placeholder"]
                )
            ]
        )
    }

    private nonisolated static func singleQuestionPayload(fromJSONObject dictionary: [String: Any]) -> DeepTutorAskUserPayload? {
        let prompt = string(dictionary["question"]) ?? string(dictionary["prompt"])
        guard let prompt, isValidPrompt(prompt) else { return nil }
        let optionsRaw = dictionary["options"] as? [Any] ?? []
        let options = optionsRaw.enumerated().compactMap { index, item in
            option(from: item, questionIndex: 0, optionIndex: index)
        }
        return DeepTutorAskUserPayload(
            intro: string(dictionary["intro"]),
            questions: [
                DeepTutorAskUserQuestion(
                    id: "q1",
                    header: nil,
                    prompt: prompt,
                    options: options,
                    multiSelect: bool(dictionary["multi_select"]) ?? bool(dictionary["multiSelect"]) ?? false,
                    allowFreeText: bool(dictionary["allow_free_text"]) ?? bool(dictionary["allows_other"]) ?? true,
                    placeholder: string(dictionary["placeholder"])
                )
            ]
        )
    }

    private nonisolated static func parseOptions(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        if let data = raw.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return array.compactMap { item in
                if let dictionary = item as? [String: Any] {
                    return string(dictionary["label"]) ?? string(dictionary["text"])
                }
                return string(item)
            }
        }
        return raw
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private nonisolated static func intro(from arguments: [String: String]) -> String? {
        let intro = arguments["intro"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return intro?.isEmpty == false ? intro : nil
    }

    private nonisolated static func selectionMode(_ dictionary: [String: Any]) -> String? {
        string(dictionary["selection_mode"])?.lowercased()
    }

    private nonisolated static func parseBool(_ raw: String?) -> Bool? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              raw.isEmpty == false else {
            return nil
        }
        if ["true", "1", "yes", "y"].contains(raw) { return true }
        if ["false", "0", "no", "n"].contains(raw) { return false }
        return nil
    }

    private nonisolated static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? String { return parseBool(value) }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private nonisolated static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }
}
