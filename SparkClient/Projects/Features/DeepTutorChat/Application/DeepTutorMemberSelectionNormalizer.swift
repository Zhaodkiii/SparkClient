import Foundation

enum DeepTutorMemberSelectionNormalizer: Sendable {
    nonisolated static func isMemberSelectionTool(_ toolName: String?) -> Bool {
        guard let toolName else { return false }
        return toolName == SparkToolName.requestMemberSelection.rawValue
    }

    nonisolated static func reason(from arguments: [String: String]) -> String {
        let raw = arguments["reason"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty {
            return "继续前，请选择本次要使用的成员档案。"
        }
        return raw
    }

    nonisolated static func arguments(from partial: ChatAssistantPartialDelta) -> [String: String] {
        if let args = partial.toolInvocationArguments, args.isEmpty == false {
            return args
        }
        guard let raw = partial.toolArguments,
              raw.isEmpty == false,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.reduce(into: [String: String]()) { result, entry in
            if let value = entry.value as? String {
                result[entry.key] = value
            } else if let value = entry.value as? CustomStringConvertible {
                result[entry.key] = String(describing: value)
            }
        }
    }
}
