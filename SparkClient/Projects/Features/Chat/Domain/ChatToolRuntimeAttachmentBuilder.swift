import Foundation

/// 工具运行态附件构建器：
/// - 统一产出 toolName/toolContent/operationalState/operationalDescription；
/// - 被“流式显示链路”和“最终落库链路”共同复用；
/// - 目标是消除重复规则，避免两条链路展示不一致。
struct ChatToolRuntimeAttachmentBuilder: Sendable {
    func build(toolName: String?, toolContent: String?) -> [ChatAttachment] {
        var attachments: [ChatAttachment] = []

        let normalizedName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalizedName.isEmpty == false {
            attachments.append(ChatAttachment(type: ChatStreamFieldKey.toolName, text: normalizedName))
        }

        let normalizedContent = toolContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard normalizedContent.isEmpty == false else {
            return attachments
        }

        attachments.append(ChatAttachment(type: ChatStreamFieldKey.toolContent, text: normalizedContent))

        // operationalState/operationalDescription 与 AI_HLY 的语义保持一致：
        // 1) state 显示当前“正在使用工具”；
        // 2) description 承载更长的过程文本。
        let lines = normalizedContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let stateText: String
        if let first = lines.first, first.hasPrefix("使用工具：") {
            stateText = first
        } else if normalizedName.isEmpty == false {
            stateText = "正在使用工具：\(normalizedName)"
        } else {
            stateText = "正在使用工具"
        }
        attachments.append(ChatAttachment(type: ChatStreamFieldKey.operationalState, text: stateText))

        let description = lines.dropFirst().joined(separator: "\n")
        if description.isEmpty == false {
            attachments.append(ChatAttachment(type: ChatStreamFieldKey.operationalDescription, text: description))
        }
        return attachments
    }
}
