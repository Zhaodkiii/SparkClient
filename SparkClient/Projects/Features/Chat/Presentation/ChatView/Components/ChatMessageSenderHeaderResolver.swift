import Foundation

/// assistant 消息发送者身份：只认消息自身的 `sender` / `modelName`，不扫描简介卡。
enum ChatMessageSenderHeaderResolver {
    /// 决定某条 assistant 消息的发送者头部类型。
    /// 1) `sender.actorType == doctor` → 医生（每条独立判定，不依赖窗口）
    /// 2) 有效 `modelName` → AI 模型
    static func senderKind(
        for message: ChatMessage,
        scenarioModels: [AIScenarioRemoteModelRow]
    ) -> ChatMessageSenderKind? {
        guard message.role == .assistant else { return nil }

        if let sender = message.sender, sender.actorType == .doctor {
            return doctorKind(from: sender)
        }

        return aiModelKind(for: message, scenarioModels: scenarioModels)
    }

    /// 真人医生每条都显示头像；AI 连续同模型只在第一条显示头部。
    static func shouldShowSenderHeader(
        for message: ChatMessage,
        in visibleMessages: [ChatMessage]
    ) -> Bool {
        guard message.role == .assistant else { return false }
        if message.sender?.actorType == .doctor {
            return true
        }
        guard let idx = visibleMessages.firstIndex(where: { $0.id == message.id }), idx > 0 else {
            return true
        }
        let previous = visibleMessages[idx - 1]
        guard previous.role == .assistant else { return true }
        return senderIdentityKey(for: previous) != senderIdentityKey(for: message)
    }

    /// 与底部模型选择器一致：自定义 `icon` 优先用 SF Symbol，否则用公司 logo。
    static func icon(for row: AIScenarioRemoteModelRow?) -> ChatSenderIcon {
        let customIcon = row?.icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if customIcon.isEmpty == false {
            return .systemName(customIcon)
        }
        return .companyLogo(companyIconName(for: row?.company ?? ""))
    }

    static func surnameCharacter(from displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "?" }
        return String(trimmed.prefix(1))
    }

    /// 服务端快照常为「开开 · 真人医生」，气泡旁只展示医生名。
    static func doctorShortDisplayName(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = " · 真人医生"
        if trimmed.hasSuffix(suffix) {
            return String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? "医生" : trimmed
    }

    /// 医生用 `doctor:{actorId}`，AI 用 `model:{modelName}`。
    static func senderIdentityKey(for message: ChatMessage) -> String? {
        guard message.role == .assistant else { return nil }
        if message.sender?.actorType == .doctor {
            let actorId = message.sender?.actorId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if actorId.isEmpty == false {
                return "doctor:\(actorId)"
            }
            let displayName = message.sender?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "doctor:\(displayName.isEmpty ? "doctor" : displayName)"
        }
        let trimmed = message.modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty == false, trimmed != "user" {
            return "model:\(trimmed)"
        }
        return nil
    }

    private static func aiModelKind(
        for message: ChatMessage,
        scenarioModels: [AIScenarioRemoteModelRow]
    ) -> ChatMessageSenderKind? {
        let trimmedModelName = message.modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedModelName.isEmpty == false, trimmedModelName != "user" else { return nil }
        let row = scenarioModels.first(where: { $0.name == trimmedModelName })
        return .aiModel(displayName: row?.displayTitle ?? trimmedModelName, icon: icon(for: row))
    }

    private static func doctorKind(from sender: ChatMessageSender) -> ChatMessageSenderKind {
        .doctor(
            displayName: doctorShortDisplayName(from: sender.displayName ?? "医生"),
            avatarURL: sender.avatarUrl
        )
    }
}
