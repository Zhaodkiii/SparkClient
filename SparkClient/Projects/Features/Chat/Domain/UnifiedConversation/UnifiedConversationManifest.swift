import Foundation

/// CHAT-000057 D-019/D-020：统一消息会话 Manifest 的本地业务绑定。
///
/// Manifest 是「这条 Thread 是什么会话、属于哪个成员、当前是否可见、服务状态如何」
/// 的唯一业务事实源；消息正文、摘要、未读仍由 ChatThread/ChatMessage 承担。
struct UnifiedConversationBinding: Codable, Equatable, Sendable {
    let threadID: UUID
    let kind: ConversationKind
    let memberID: Int?
    let serviceStatus: ConversationServiceStatus
    let identity: UnifiedConversationIdentity?
    /// 单 Thread 业务绑定版本，单调递增；乱序/旧版本变更不得覆盖新版本（含删除墓碑）。
    let bindingRevision: Int64
    let updatedAt: Date
    /// delete 事件以墓碑形式持久化，防止旧 upsert 回包复活已撤权会话。
    let isDeleted: Bool
    let deleteReason: String?

    nonisolated init(
        threadID: UUID,
        kind: ConversationKind,
        memberID: Int?,
        serviceStatus: ConversationServiceStatus,
        identity: UnifiedConversationIdentity?,
        bindingRevision: Int64,
        updatedAt: Date,
        isDeleted: Bool = false,
        deleteReason: String? = nil
    ) {
        self.threadID = threadID
        self.kind = kind
        self.memberID = memberID
        self.serviceStatus = serviceStatus
        self.identity = identity
        self.bindingRevision = bindingRevision
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.deleteReason = deleteReason
    }

    /// 撤权/删除类原因：会话必须从列表、搜索、未读聚合与身份缓存中移除。
    var isAccessRevoked: Bool {
        if isDeleted { return true }
        guard let deleteReason else { return false }
        switch deleteReason {
        case "permission_revoked", "member_access_revoked", "account_access_revoked",
             "service_removed", "binding_deleted", "thread_deleted":
            return true
        default:
            return false
        }
    }
}

/// CHAT-000057 29.4：Manifest identity 最小身份引用（不含病历/消息正文/敏感标识）。
struct UnifiedConversationIdentity: Codable, Equatable, Sendable {
    let hospitalID: UUID?
    let doctorID: UUID?
    let agentID: UUID?
    let doctorDisplayName: String?
    let agentDisplayName: String?
    let departmentDisplayName: String?
    let hospitalDisplayName: String?
    let doctorAvatarURLString: String?
    /// 线上问诊预留
    let consultationID: UUID?
    let consultationDisplayName: String?

    nonisolated init(
        hospitalID: UUID? = nil,
        doctorID: UUID? = nil,
        agentID: UUID? = nil,
        doctorDisplayName: String? = nil,
        agentDisplayName: String? = nil,
        departmentDisplayName: String? = nil,
        hospitalDisplayName: String? = nil,
        doctorAvatarURLString: String? = nil,
        consultationID: UUID? = nil,
        consultationDisplayName: String? = nil
    ) {
        self.hospitalID = hospitalID
        self.doctorID = doctorID
        self.agentID = agentID
        self.doctorDisplayName = doctorDisplayName
        self.agentDisplayName = agentDisplayName
        self.departmentDisplayName = departmentDisplayName
        self.hospitalDisplayName = hospitalDisplayName
        self.doctorAvatarURLString = doctorAvatarURLString
        self.consultationID = consultationID
        self.consultationDisplayName = consultationDisplayName
    }
}

/// CHAT-000057 D-020：账号级 Manifest 同步状态（cursor 与 binding 缓存同事务提交）。
struct UnifiedConversationManifestSyncState: Codable, Equatable, Sendable {
    let accountID: Int64
    var schemaVersion: Int
    var appliedCursor: String?
    var lastSuccessfulSyncAt: Date?
    var needsFullRebuild: Bool

    nonisolated init(
        accountID: Int64,
        schemaVersion: Int = UnifiedConversationManifestSchema.currentVersion,
        appliedCursor: String? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        needsFullRebuild: Bool = false
    ) {
        self.accountID = accountID
        self.schemaVersion = schemaVersion
        self.appliedCursor = appliedCursor
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.needsFullRebuild = needsFullRebuild
    }
}

nonisolated enum UnifiedConversationManifestSchema {
    /// 客户端支持的 Manifest 协议版本；不兼容时停止应用变更，不按未知字段猜测类型。
    static let currentVersion = 1
}

/// CHAT-000057 45.1：统一消息能力发布开关。
/// 服务端关闭/未上线时必须能回到旧 scope 兼容路径；开关关闭不删除任何本地消息事实。
struct UnifiedConversationFeatureFlags: Equatable, Sendable {
    /// 是否请求/消费服务端 Manifest。服务端未上线前为 false，分类走 scope + provenance + 旧普通会话兼容路径。
    let manifestEnabled: Bool
    /// 是否启用 unknown 安全门控（确认前禁发/禁已读）。仅 Manifest 生效后才有意义。
    let unknownGatingEnabled: Bool
    /// 是否把原普通对话 UI 切换为统一消息 UI（阶段 3）；false 时回退旧普通对话列表。
    let unifiedMessageListEnabled: Bool
    /// 统一消息中是否显示已确认医院 Thread；false 时回退 CHAT-000054 医院 Thread 排除行为。
    let hospitalThreadInUnifiedMessagesEnabled: Bool

    nonisolated init(
        manifestEnabled: Bool,
        unknownGatingEnabled: Bool,
        unifiedMessageListEnabled: Bool = true,
        hospitalThreadInUnifiedMessagesEnabled: Bool = true
    ) {
        self.manifestEnabled = manifestEnabled
        self.unknownGatingEnabled = unknownGatingEnabled
        self.unifiedMessageListEnabled = unifiedMessageListEnabled
        self.hospitalThreadInUnifiedMessagesEnabled = hospitalThreadInUnifiedMessagesEnabled
    }

    /// 当前默认：Manifest 服务端尚未上线、unknown 门控未开启（阶段 4 前兼容旧行为）；
    /// 统一消息 UI 与医院 Thread 混排默认开启，支持服务端/本地开关回退。
    static let current = UnifiedConversationFeatureFlags(
        manifestEnabled: UnifiedConversationFeatureFlags.readOverride(
            key: "unified_conversation_manifest_enabled",
            defaultValue: false
        ),
        unknownGatingEnabled: UnifiedConversationFeatureFlags.readOverride(
            key: "unknown_thread_confirmation_enabled",
            defaultValue: false
        ),
        unifiedMessageListEnabled: UnifiedConversationFeatureFlags.readOverride(
            key: "unified_message_list_enabled",
            defaultValue: true
        ),
        hospitalThreadInUnifiedMessagesEnabled: UnifiedConversationFeatureFlags.readOverride(
            key: "hospital_thread_in_unified_messages_enabled",
            defaultValue: true
        )
    )

    private static func readOverride(key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }
}
