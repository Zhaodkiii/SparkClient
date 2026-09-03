import Foundation

/// CHAT-000057：统一消息列表的会话业务分类。
///
/// 分类事实源优先级：服务端 Manifest binding → 医院 conversation scope（已验证本地缓存）
/// → 可验证本地创建来源（manual_ordinary_ai）→ unknown。
/// 禁止通过标题、头像、scenario 或消息内容猜测类型。
enum ConversationKind: String, Codable, Sendable, CaseIterable {
    /// 普通 AI 对话
    case ordinaryAI = "ordinary_ai"
    /// 院内医生智能体对话
    case hospitalAgent = "hospital_agent"
    /// 线上问诊对话（本期仅预留，不产生真实列表项）
    case telemedicine = "telemedicine"
    /// 暂时无法判定（Manifest 未覆盖、旧数据或协议异常）；仅客户端使用，服务端不下发该值
    case unknown = "unknown"
}

/// CHAT-000057 D-020/D-023/D-024：分类确认状态。
enum ConversationClassificationState: String, Codable, Sendable {
    /// 类型、成员与权限已确认
    case resolved
    /// 正在确认（首次同步或打开时触发）
    case resolving
    /// 确认失败但可重试（网络/服务端暂时异常）
    case retryableFailure
    /// 两个业务绑定声称同一 threadID，进入受控错误态
    case conflict
    /// 已撤权/已删除；正常不产生列表卡片，仅用于打开中的会话安全退出
    case revoked
}

/// CHAT-000057 D-023：可操作性结构化输出。
/// View 不得以 `kind != hospitalAgent` 推导普通 AI 能力，所有行为只读取 capability。
struct ConversationCapability: Equatable, Sendable {
    let canRead: Bool
    let canSend: Bool
    let canUseAI: Bool
    let canUseHospitalKnowledge: Bool
    let canUseTelemedicine: Bool
    let canMarkRead: Bool

    nonisolated init(
        canRead: Bool,
        canSend: Bool,
        canUseAI: Bool,
        canUseHospitalKnowledge: Bool,
        canUseTelemedicine: Bool,
        canMarkRead: Bool
    ) {
        self.canRead = canRead
        self.canSend = canSend
        self.canUseAI = canUseAI
        self.canUseHospitalKnowledge = canUseHospitalKnowledge
        self.canUseTelemedicine = canUseTelemedicine
        self.canMarkRead = canMarkRead
    }

    /// 普通 AI：完整能力
    static let ordinaryAI = ConversationCapability(
        canRead: true,
        canSend: true,
        canUseAI: true,
        canUseHospitalKnowledge: false,
        canUseTelemedicine: false,
        canMarkRead: true
    )

    /// 院内医生智能体（AI 服务中）：可发送、AI 自动回复、知识库同步
    static let hospitalAgentActive = ConversationCapability(
        canRead: true,
        canSend: true,
        canUseAI: true,
        canUseHospitalKnowledge: true,
        canUseTelemedicine: false,
        canMarkRead: true
    )

    /// 院内医生智能体（医生接管中）：可发送，AI 不自动回复
    static let hospitalAgentTakenOver = ConversationCapability(
        canRead: true,
        canSend: true,
        canUseAI: false,
        canUseHospitalKnowledge: true,
        canUseTelemedicine: false,
        canMarkRead: true
    )

    /// 医疗服务暂停/下架/结束：历史可读，禁止发送
    static let medicalReadOnly = ConversationCapability(
        canRead: true,
        canSend: false,
        canUseAI: false,
        canUseHospitalKnowledge: false,
        canUseTelemedicine: false,
        canMarkRead: true
    )

    /// unknown / 确认中：全部禁用；历史读取需经详情级权限校验，不在列表能力内放开
    static let unknownReadOnly = ConversationCapability(
        canRead: false,
        canSend: false,
        canUseAI: false,
        canUseHospitalKnowledge: false,
        canUseTelemedicine: false,
        canMarkRead: false
    )

    /// 撤权/删除：无任何能力
    static let revoked = ConversationCapability(
        canRead: false,
        canSend: false,
        canUseAI: false,
        canUseHospitalKnowledge: false,
        canUseTelemedicine: false,
        canMarkRead: false
    )
}

/// CHAT-000057 D-021：医疗服务状态（受控枚举，未知服务端值映射为 unsupported，不猜测）。
enum ConversationServiceStatus: Equatable, Sendable, Codable {
    /// AI 服务中
    case active
    /// 医生接管中（需求矩阵值 doctor_taken_over）
    case doctorTakenOver
    /// 医生已接管（服务端 context 接口实际下发值 doctor_joined，语义同 doctorTakenOver）
    case doctorJoined
    /// 服务已结束
    case ended
    /// 服务暂停
    case suspended
    /// 智能体已下架/未发布
    case agentUnavailable
    /// 医院服务暂不可用
    case hospitalUnavailable
    /// 线上问诊已结束（预留）
    case consultationCompleted
    /// 服务端下发了客户端未识别的状态；按只读处理
    case unsupported(String)

    nonisolated init(rawValue: String) {
        switch rawValue {
        case "active": self = .active
        case "doctor_taken_over": self = .doctorTakenOver
        case "doctor_joined": self = .doctorJoined
        case "ended": self = .ended
        case "suspended": self = .suspended
        case "agent_unpublished", "agent_offline", "agent_unavailable": self = .agentUnavailable
        case "hospital_service_unavailable": self = .hospitalUnavailable
        case "consultation_completed": self = .consultationCompleted
        default: self = .unsupported(rawValue)
        }
    }

    nonisolated var rawValue: String {
        switch self {
        case .active: return "active"
        case .doctorTakenOver: return "doctor_taken_over"
        case .doctorJoined: return "doctor_joined"
        case .ended: return "ended"
        case .suspended: return "suspended"
        case .agentUnavailable: return "agent_unavailable"
        case .hospitalUnavailable: return "hospital_service_unavailable"
        case .consultationCompleted: return "consultation_completed"
        case .unsupported(let value): return value
        }
    }

    /// 是否为可继续发送的服务状态（医生接管中仍可发送）。
    var allowsSending: Bool {
        switch self {
        case .active, .doctorTakenOver, .doctorJoined:
            return true
        case .ended, .suspended, .agentUnavailable, .hospitalUnavailable, .consultationCompleted, .unsupported:
            return false
        }
    }

    /// 医生接管中（doctor_taken_over / doctor_joined）：患者可发送，AI 不自动回复（38.6）。
    var isDoctorTakeover: Bool {
        switch self {
        case .doctorTakenOver, .doctorJoined:
            return true
        case .active, .ended, .suspended, .agentUnavailable, .hospitalUnavailable,
             .consultationCompleted, .unsupported:
            return false
        }
    }

    /// 卡片主状态文案；active 返回 nil（不显示状态标签，避免噪声）。
    var localizedBadge: String? {
        switch self {
        case .active:
            return nil
        case .doctorTakenOver, .doctorJoined:
            return L10n.text("chat.unified.status.doctor_taken_over", fallback: "医生接管中")
        case .ended:
            return L10n.text("chat.unified.status.ended", fallback: "服务已结束")
        case .suspended:
            return L10n.text("chat.unified.status.suspended", fallback: "服务暂停")
        case .agentUnavailable:
            return L10n.text("chat.unified.status.agent_unavailable", fallback: "智能体暂不可用")
        case .hospitalUnavailable:
            return L10n.text("chat.unified.status.hospital_unavailable", fallback: "医院服务暂不可用")
        case .consultationCompleted:
            return L10n.text("chat.unified.status.consultation_completed", fallback: "问诊已结束")
        case .unsupported:
            return L10n.text("chat.unified.status.unavailable", fallback: "服务暂不可用")
        }
    }

    /// 只读会话页禁用输入的患者可见原因。
    var localizedReadOnlyReason: String? {
        switch self {
        case .active, .doctorTakenOver, .doctorJoined:
            return nil
        case .ended:
            return L10n.text("chat.unified.readonly.ended", fallback: "该医生智能体当前已结束服务，您仍可查看历史咨询记录")
        case .suspended:
            return L10n.text("chat.unified.readonly.suspended", fallback: "该医生智能体服务已暂停，您仍可查看历史咨询记录")
        case .agentUnavailable:
            return L10n.text("chat.unified.readonly.agent_unavailable", fallback: "该医生智能体暂不可用，您仍可查看历史咨询记录")
        case .hospitalUnavailable:
            return L10n.text("chat.unified.readonly.hospital_unavailable", fallback: "医院服务暂不可用，您仍可查看历史咨询记录")
        case .consultationCompleted:
            return L10n.text("chat.unified.readonly.consultation_completed", fallback: "本次问诊已结束，您仍可查看历史记录")
        case .unsupported:
            return L10n.text("chat.unified.readonly.unavailable", fallback: "服务暂不可用，您仍可查看历史咨询记录")
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self.init(rawValue: rawValue)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// CHAT-000057 D-007/D-017：卡片类型标识（结构化值，View 不解析服务端字符串）。
enum ConversationTypeBadge: Equatable, Sendable {
    case ordinaryAI
    case hospitalAgent
    case telemedicine
    /// unknown 确认中
    case confirming
    /// unknown 确认失败（暂无法确认）
    case confirmationFailed

    var localizedTitle: String {
        switch self {
        case .ordinaryAI:
            return L10n.text("chat.unified.badge.ai", fallback: "AI 对话")
        case .hospitalAgent:
            return L10n.text("chat.unified.badge.hospital_agent", fallback: "医生智能体")
        case .telemedicine:
            return L10n.text("chat.unified.badge.telemedicine", fallback: "线上问诊")
        case .confirming:
            return L10n.text("chat.unified.badge.confirming", fallback: "会话信息确认中")
        case .confirmationFailed:
            return L10n.text("chat.unified.badge.confirmation_failed", fallback: "暂无法确认")
        }
    }
}

/// CHAT-000057 D-017：消息列表顶部类型筛选（纯 UI 状态，不持久化、不改写业务事实）。
enum MessageListTypeFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case ordinaryAI
    case hospitalAgent
    case telemedicine

    var localizedTitle: String {
        switch self {
        case .all:
            return L10n.text("chat.unified.filter.all", fallback: "全部")
        case .ordinaryAI:
            return L10n.text("chat.unified.filter.ai", fallback: "AI 对话")
        case .hospitalAgent:
            return L10n.text("chat.unified.filter.hospital_agent", fallback: "医生智能体")
        case .telemedicine:
            return L10n.text("chat.unified.filter.telemedicine", fallback: "线上问诊")
        }
    }

    /// unknown 会话只在「全部」筛选中可见，不进入任何具体类型筛选。
    func matches(_ kind: ConversationKind) -> Bool {
        switch self {
        case .all:
            return true
        case .ordinaryAI:
            return kind == .ordinaryAI
        case .hospitalAgent:
            return kind == .hospitalAgent
        case .telemedicine:
            return kind == .telemedicine
        }
    }
}
