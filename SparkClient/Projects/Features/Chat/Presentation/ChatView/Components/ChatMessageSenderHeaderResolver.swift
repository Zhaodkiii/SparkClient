import Foundation

/// 医院会话内 assistant 头部展示的补充上下文（身份仍只认消息 `sender` / `modelName`）。
struct ChatMessageSenderHeaderContext: Equatable, Sendable {
    /// 医生显示名（运行配置 / 目录），用于覆盖 sender 快照里的智能体 product 名。
    var hospitalDoctorDisplayName: String?
    /// 医院专用锁定模型行；Pro 场景列表未包含时仍可用 `displayTitle`。
    var hospitalLockedModelRow: AIScenarioRemoteModelRow?

    static let empty = ChatMessageSenderHeaderContext()
}

/// assistant 消息发送者身份：类型只认消息自身的 `sender` / `modelName`。
enum ChatMessageSenderHeaderResolver {
    /// 决定某条 assistant 消息的发送者头部类型。
    /// 1) `sender.actorType == doctor` → 医生（每条独立判定，不依赖窗口）
    /// 2) 有效 `modelName` → AI 模型
    static func senderKind(
        for message: ChatMessage,
        scenarioModels: [AIScenarioRemoteModelRow],
        visibleMessages: [ChatMessage] = [],
        context: ChatMessageSenderHeaderContext = .empty
    ) -> ChatMessageSenderKind? {
        guard message.role == .assistant else { return nil }

        if let sender = message.sender, sender.actorType == .doctor {
            return doctorKind(from: sender)
        }

        // 医生智能体发言：展示智能体头像 + 医生显示名（非智能体 product 名）。
        if let sender = message.sender, sender.actorType == .aiAgent {
            let avatarURL = sender.avatarUrl ?? ""
            if avatarURL.isEmpty == false {
                let displayName = aiAgentHeaderDisplayName(
                    sender: sender,
                    context: context,
                    visibleMessages: visibleMessages
                )
                return .aiAgent(displayName: displayName, avatarURL: sender.avatarUrl)
            }
        }

        return aiModelKind(for: message, scenarioModels: scenarioModels, context: context)
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

    /// 医生用 `doctor:{actorId}`，带头像的智能体用 `agent:{actorId}`，其余 AI 用 `model:{modelName}`。
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
        if message.sender?.actorType == .aiAgent,
           let avatarURL = message.sender?.avatarUrl,
           avatarURL.isEmpty == false {
            let actorId = message.sender?.actorId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if actorId.isEmpty == false {
                return "agent:\(actorId)"
            }
            let displayName = message.sender?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "agent:\(displayName.isEmpty ? "agent" : displayName)"
        }
        let trimmed = message.modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty == false, trimmed != "user" {
            return "model:\(trimmed)"
        }
        return nil
    }

    private static func aiModelKind(
        for message: ChatMessage,
        scenarioModels: [AIScenarioRemoteModelRow],
        context: ChatMessageSenderHeaderContext
    ) -> ChatMessageSenderKind? {
        let trimmedModelName = message.modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedModelName.isEmpty == false, trimmedModelName != "user" else { return nil }
        let row = scenarioModelRow(
            named: trimmedModelName,
            scenarioModels: scenarioModels,
            context: context
        )
        return .aiModel(displayName: row?.displayTitle ?? trimmedModelName, icon: icon(for: row))
    }

    private static func scenarioModelRow(
        named modelName: String,
        scenarioModels: [AIScenarioRemoteModelRow],
        context: ChatMessageSenderHeaderContext
    ) -> AIScenarioRemoteModelRow? {
        if let row = scenarioModels.first(where: { $0.name == modelName }) {
            return row
        }
        if let locked = context.hospitalLockedModelRow, locked.name == modelName {
            return locked
        }
        return nil
    }

    /// 智能体消息头部：医生显示名 > 简介卡医生名 > 去掉「智能体」后缀的快照名。
    static func aiAgentHeaderDisplayName(
        sender: ChatMessageSender,
        context: ChatMessageSenderHeaderContext,
        visibleMessages: [ChatMessage]
    ) -> String {
        if let name = trimmedNonEmpty(context.hospitalDoctorDisplayName) {
            return name
        }
        if let name = doctorDisplayNameFromIntroCard(in: visibleMessages) {
            return name
        }
        let snapshot = sender.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if snapshot.isEmpty == false {
            return preferDoctorDisplayNameOverAgentName(snapshot)
        }
        return "医生"
    }

    /// 服务端 attribution 快照常为「{医生名}智能体」，气泡旁展示医生显示名。
    static func preferDoctorDisplayNameOverAgentName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = "智能体"
        if trimmed.hasSuffix(suffix) {
            let stripped = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.isEmpty == false {
                return stripped
            }
        }
        return trimmed.isEmpty ? "医生" : trimmed
    }

    static func doctorDisplayNameFromIntroCard(in messages: [ChatMessage]) -> String? {
        for message in messages {
            for block in message.blocks {
                guard case .hospitalDoctorIntroCard(let payload) = block.payload else { continue }
                if let name = trimmedNonEmpty(payload.doctor.displayName) {
                    return name
                }
            }
        }
        return nil
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false
        else {
            return nil
        }
        return trimmed
    }

    private static func doctorKind(from sender: ChatMessageSender) -> ChatMessageSenderKind {
        .doctor(
            displayName: doctorShortDisplayName(from: sender.displayName ?? "医生"),
            avatarURL: sender.avatarUrl
        )
    }
}
