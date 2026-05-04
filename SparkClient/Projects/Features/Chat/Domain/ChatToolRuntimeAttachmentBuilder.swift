import Foundation

/// 工具运行态附件构建器：
/// - 统一产出 toolName/toolContent/operationalState/operationalDescription；
/// - 被“流式显示链路”和“最终落库链路”共同复用；
/// - 目标是消除重复规则，避免两条链路展示不一致。
nonisolated struct ChatToolRuntimeAttachmentBuilder: Sendable {
    func build(toolName: String?, toolContent: String?) -> [ChatAttachment] {
        var attachments: [ChatAttachment] = []

        let normalizedName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalizedName.isEmpty == false {
            attachments.append(ChatAttachment(type: .toolName, text: normalizedName))
        }

        let normalizedContent = toolContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard normalizedContent.isEmpty == false else {
            return attachments
        }

        attachments.append(ChatAttachment(type: .toolContent, text: normalizedContent))
        if let meta = Self.makeOperationalMeta(toolName: normalizedName, toolContent: normalizedContent) {
            attachments.append(ChatAttachment(type: .operationalState, text: meta.state))
            if meta.description.isEmpty == false {
                attachments.append(ChatAttachment(type: .operationalDescription, text: meta.description))
            }
        }
        return attachments
    }

    static func makeOperationalMeta(toolName: String?, toolContent: String?) -> (state: String, description: String)? {
        let normalizedName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedContent = toolContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard normalizedContent.isEmpty == false else { return nil }

        let lines = normalizedContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let stateText = localizedOperatingState(toolName: normalizedName, firstLine: lines.first)
        let descriptionStart: Int = {
            guard let first = lines.first else { return 0 }
            return isToolStateLine(first) ? 1 : 0
        }()
        let description = lines.dropFirst(descriptionStart).joined(separator: "\n")
        return (stateText, description)
    }

    nonisolated static func localizedDisplayName(for toolName: String?) -> String {
        let normalized = toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalized.isEmpty {
            return L10n.text("chat.bubble.tool.default_name", fallback: "Tool")
        }
        let localized = SparkToolName.displayName(for: normalized)
        let fallbackKey = "ai_settings.tools.\(normalized)"
        if localized == fallbackKey {
            return normalized
        }
        return localized
    }

    private static func localizedOperatingState(toolName: String, firstLine: String?) -> String {
        let prefix = L10n.text("chat.bubble.tool.operating_prefix", fallback: "Using tool: ")
        if let firstLine, isToolStateLine(firstLine) {
            let extractedName = extractToolName(fromStateLine: firstLine)
            let displayName = localizedDisplayName(for: extractedName.isEmpty ? toolName : extractedName)
            return "\(prefix)\(displayName)"
        }
        let displayName = localizedDisplayName(for: toolName)
        return "\(prefix)\(displayName)"
    }

    private static func isToolStateLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            L10n.text("chat.bubble.tool.operating_prefix", fallback: "Using tool: "),
            "正在使用工具：",
            "使用工具：",
            "Using tool: "
        ]
        return prefixes.contains { trimmed.hasPrefix($0) }
    }

    private static func extractToolName(fromStateLine line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            L10n.text("chat.bubble.tool.operating_prefix", fallback: "Using tool: "),
            "正在使用工具：",
            "使用工具：",
            "Using tool: "
        ]
        for prefix in prefixes where trimmed.hasPrefix(prefix) {
            let raw = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return raw
        }
        return ""
    }
}
