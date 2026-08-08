import Foundation

protocol DeepTutorTool: Sendable {
    var name: DeepTutorToolName { get }
    func definition() -> AIRuntimeToolDefinition
    func execute(arguments: [String: Any], context: DeepTutorToolContext) async -> DeepTutorToolResult
}

struct DeepTutorToolRegistry: Sendable {
    private let tools: [String: any DeepTutorTool]

    init(tools: [any DeepTutorTool]) {
        var mapped: [String: any DeepTutorTool] = [:]
        for tool in tools {
            mapped[tool.name.rawValue] = tool
        }
        self.tools = mapped
    }

    func tool(named name: String) -> (any DeepTutorTool)? {
        tools[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    func compose(context: DeepTutorToolContext, modelAllowedToolNames: Set<String>?) -> DeepTutorToolRuntimeCompositionResult {
        var names: [String] = [
            DeepTutorToolName.askUser.rawValue,
            DeepTutorToolName.getCurrentMemberBinding.rawValue,
            DeepTutorToolName.requestMemberSelection.rawValue,
            DeepTutorToolName.writeMemory.rawValue,
        ]

        if context.hasMemory {
            names.append(DeepTutorToolName.readMemory.rawValue)
        }

        let allowed = modelAllowedToolNames.map { Set($0.map(Self.normalize)) }
        let deduped = Array(NSOrderedSet(array: names).compactMap { $0 as? String })
            .filter { name in
                guard let allowed else { return true }
                return allowed.contains(Self.normalize(name))
            }
            .filter { tools[$0] != nil }

        let schemas = deduped.compactMap { tools[$0]?.definition() }
        return DeepTutorToolRuntimeCompositionResult(
            enabledToolNames: deduped,
            schemas: schemas,
            promptManifest: Self.promptManifest(
                toolNames: deduped,
                hasBoundMember: context.boundMemberID != nil
            ),
            reason: "deeptutor_phase1"
        )
    }

    func execute(name: String, arguments: [String: Any], context: DeepTutorToolContext) async -> DeepTutorToolResult {
        guard let tool = tool(named: name) else {
            return DeepTutorToolResult(
                content: "Tool '\(name)' is not available in this DeepTutorChat turn.",
                success: false
            )
        }
        return await tool.execute(arguments: arguments, context: context)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func promptManifest(toolNames: [String], hasBoundMember: Bool) -> String {
        guard toolNames.isEmpty == false else { return "" }
        let joined = toolNames.map { "- \($0)" }.joined(separator: "\n")
        let memberStateHint = hasBoundMember
            ? "当前会话已经绑定了成员；默认使用该成员，只有用户明确要求切换时才请求重新选择。"
            : "当前会话未绑定成员；如果问题需要成员上下文，先检查绑定状态，再请求用户选择成员。"

        return """

        # DeepTutor Tools
        本轮可使用以下 DeepTutorChat 原生工具：
        \(joined)

        工具规则：
        - 先调用 get_current_member_binding 检查当前会话是否已绑定成员。
        - \(memberStateHint)
        - 如果需要成员上下文且当前没有成员，先调用 request_member_selection，并在用户选择后继续原始请求。
        - 如果当前已绑定成员，但用户明确要求切换成员，先调用 request_member_selection 让用户确认。
        - 只有真正缺少用户决策时才调用 ask_user；不要问“是否继续”，不要确认用户已经说清楚的信息。
        - read_memory 只用于个性化语气、深度、格式和偏好。
        - write_memory 只保存用户明确表达的长期偏好，不保存医疗诊断、体检异常、家族史或模型推断。
        - ask_user 或 request_member_selection 解决后，必须继续完成用户的原始请求，不要只回复确认。
        """
    }
}

struct DeepTutorToolArgumentDecoder: Sendable {
    static func parse(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    static func summary(_ arguments: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(arguments),
              let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    static func string(_ arguments: [String: Any], _ key: String) -> String? {
        if let value = arguments[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    static func bool(_ arguments: [String: Any], _ key: String, default defaultValue: Bool = false) -> Bool {
        if let value = arguments[key] as? Bool { return value }
        if let value = arguments[key] as? String {
            return ["true", "yes", "1"].contains(value.lowercased())
        }
        return defaultValue
    }
}
