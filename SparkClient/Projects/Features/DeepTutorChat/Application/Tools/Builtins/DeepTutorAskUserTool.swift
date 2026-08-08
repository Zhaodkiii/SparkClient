import Foundation

struct DeepTutorAskUserTool: DeepTutorTool {
    let name: DeepTutorToolName = .askUser

    func definition() -> AIRuntimeToolDefinition {
        AIRuntimeToolDefinition(
            name: name.rawValue,
            summary: "Pause the conversation to ask the user 1-4 clarifying questions in one card. Use only when blocked on a decision that is genuinely the user's to make.",
            properties: [
                "intro": AIRuntimeToolProperty(
                    type: "string",
                    description: "Optional one-line lead-in shown above the questions."
                ),
                "questions": AIRuntimeToolProperty(
                    type: "array",
                    description: "1-4 questions to ask in one card. Bundle all clarifications into this single call.",
                    arrayItems: AIRuntimeToolProperty(
                        type: "object",
                        description: "Clarifying question",
                        objectProperties: [
                            "id": AIRuntimeToolProperty(type: "string", description: "Stable question id."),
                            "header": AIRuntimeToolProperty(type: "string", description: "Very short tab label, max 12 chars."),
                            "prompt": AIRuntimeToolProperty(type: "string", description: "The complete question text."),
                            "options": AIRuntimeToolProperty(
                                type: "array",
                                description: "2-4 concise options when useful.",
                                arrayItems: AIRuntimeToolProperty(
                                    type: "object",
                                    description: "Option",
                                    objectProperties: [
                                        "label": AIRuntimeToolProperty(type: "string", description: "Concise option label."),
                                        "description": AIRuntimeToolProperty(type: "string", description: "What this option means.")
                                    ],
                                    objectRequired: ["label"]
                                )
                            ),
                            "multi_select": AIRuntimeToolProperty(type: "boolean", description: "Whether multiple options may be selected."),
                            "allow_free_text": AIRuntimeToolProperty(type: "boolean", description: "Whether free text is allowed."),
                            "placeholder": AIRuntimeToolProperty(type: "string", description: "Free text placeholder.")
                        ],
                        objectRequired: ["prompt"]
                    )
                )
            ],
            required: ["questions"]
        )
    }

    func execute(arguments: [String: Any], context: DeepTutorToolContext) async -> DeepTutorToolResult {
        let built = Self.payload(from: arguments)
        guard let payload = built.payload else {
            return DeepTutorToolResult(content: built.error ?? "Invalid ask_user arguments.", success: false)
        }
        let prompts = payload.questions.map(\.prompt).joined(separator: ", ")
        return DeepTutorToolResult(
            content: "[awaiting user reply to: \(prompts)]",
            metadata: [
                "pause": "ask_user",
                "ask_user": Self.encodePayload(payload),
            ],
            pauseForUser: .askUser(payload)
        )
    }

    private static func payload(from arguments: [String: Any]) -> (payload: DeepTutorAskUserPayload?, error: String?) {
        let intro = clipped(DeepTutorToolArgumentDecoder.string(arguments, "intro"), max: 400)
        let rawQuestions: [[String: Any]]
        if let questions = arguments["questions"] as? [[String: Any]] {
            rawQuestions = questions
        } else if let questions = arguments["questions"] as? [Any] {
            rawQuestions = questions.compactMap { $0 as? [String: Any] }
        } else if let question = DeepTutorToolArgumentDecoder.string(arguments, "question") {
            var legacy: [String: Any] = ["prompt": question]
            if let options = arguments["options"] {
                legacy["options"] = options
            }
            rawQuestions = [legacy]
        } else {
            return (nil, "`questions` must contain at least one question.")
        }
        guard rawQuestions.isEmpty == false else {
            return (nil, "`questions` must contain at least one question.")
        }
        var usedIDs: Set<String> = []
        var questions: [DeepTutorAskUserQuestion] = []
        for (index, raw) in rawQuestions.prefix(4).enumerated() {
            guard let prompt = clipped(DeepTutorToolArgumentDecoder.string(raw, "prompt"), max: 800),
                  prompt.isEmpty == false else {
                return (nil, "Question #\(index + 1): `prompt` must be a non-empty string.")
            }
            let baseID = clipped(DeepTutorToolArgumentDecoder.string(raw, "id"), max: 48) ?? "q\(index + 1)"
            let id = uniqueID(baseID, used: &usedIDs)
            let allowFreeText = DeepTutorToolArgumentDecoder.bool(raw, "allow_free_text", default: true)
            questions.append(
                DeepTutorAskUserQuestion(
                    id: id,
                    header: clipped(DeepTutorToolArgumentDecoder.string(raw, "header"), max: 16),
                    prompt: prompt,
                    options: optionPayloads(from: raw["options"], allowFreeText: allowFreeText),
                    multiSelect: DeepTutorToolArgumentDecoder.bool(raw, "multi_select")
                        || DeepTutorToolArgumentDecoder.bool(raw, "multiSelect"),
                    allowFreeText: allowFreeText,
                    placeholder: clipped(DeepTutorToolArgumentDecoder.string(raw, "placeholder"), max: 120)
                )
            )
        }
        guard questions.isEmpty == false else {
            return (nil, "`questions` must contain at least one valid question.")
        }
        return (DeepTutorAskUserPayload(intro: intro, questions: questions), nil)
    }

    private static func optionPayloads(from raw: Any?, allowFreeText: Bool) -> [DeepTutorAskUserOption] {
        let rawOptions: [[String: Any]]
        if let objects = raw as? [[String: Any]] {
            rawOptions = objects
        } else if let anyOptions = raw as? [Any] {
            rawOptions = anyOptions.map { item in
                if let object = item as? [String: Any] {
                    return object
                }
                return ["label": String(describing: item)]
            }
        } else if let strings = raw as? [String] {
            rawOptions = strings.map { ["label": $0] }
        } else {
            rawOptions = []
        }

        var seen: Set<String> = []
        return rawOptions.prefix(8).compactMap { raw -> DeepTutorAskUserOption? in
            guard let label = clipped(DeepTutorToolArgumentDecoder.string(raw, "label"), max: 120),
                  label.isEmpty == false else {
                return nil
            }
            let key = label.lowercased()
            if allowFreeText && ["other", "其他", "其它"].contains(key) {
                return nil
            }
            guard seen.contains(key) == false else { return nil }
            seen.insert(key)
            return DeepTutorAskUserOption(
                id: UUID().uuidString,
                label: label,
                description: clipped(DeepTutorToolArgumentDecoder.string(raw, "description"), max: 200)
            )
        }
    }

    private static func clipped(_ value: String?, max: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func uniqueID(_ base: String, used: inout Set<String>) -> String {
        var candidate = base
        var suffix = 2
        while used.contains(candidate) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        used.insert(candidate)
        return candidate
    }

    private static func encodePayload(_ payload: DeepTutorAskUserPayload) -> String {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
