import Foundation

/// 聊天会话默认启动偏好。
/// 这组值只用于“新进入会话时”的初始状态，真正的会话运行时开关仍然保存在 `ChatComposerDraft.runtimeFlags`。
nonisolated struct ChatComposerStartupPreferences: Codable, Equatable, Sendable {
    var memberProfileEnabled: Bool
    var useTools: Bool
    var useKnowledgeBag: Bool
    var useWebSearch: Bool
    var reasoningEnabled: Bool
    var reasoningEffortTier: Int

    init(
        memberProfileEnabled: Bool,
        useTools: Bool,
        useKnowledgeBag: Bool,
        useWebSearch: Bool,
        reasoningEnabled: Bool,
        reasoningEffortTier: Int
    ) {
        self.memberProfileEnabled = memberProfileEnabled
        self.useTools = useTools
        self.useKnowledgeBag = useKnowledgeBag
        self.useWebSearch = useWebSearch
        self.reasoningEnabled = reasoningEnabled
        self.reasoningEffortTier = reasoningEffortTier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKey.self)
        let fallback = ChatComposerStartupPreferences.fallback
        memberProfileEnabled = try container.decodeIfPresent(Bool.self, forKey: .key("memberProfileEnabled"))
            ?? fallback.memberProfileEnabled
        useTools = try container.decodeIfPresent(Bool.self, forKey: .key("useTools"))
            ?? fallback.useTools
        useKnowledgeBag = try container.decodeIfPresent(Bool.self, forKey: .key("useKnowledgeBag"))
            ?? fallback.useKnowledgeBag
        useWebSearch = try container.decodeIfPresent(Bool.self, forKey: .key("useWebSearch"))
            ?? fallback.useWebSearch
        reasoningEnabled = try container.decodeIfPresent(Bool.self, forKey: .key("reasoningEnabled"))
            ?? fallback.reasoningEnabled
        reasoningEffortTier = try container.decodeIfPresent(Int.self, forKey: .key("reasoningEffortTier"))
            ?? fallback.reasoningEffortTier
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodableKey.self)
        try container.encode(memberProfileEnabled, forKey: .key("memberProfileEnabled"))
        try container.encode(useTools, forKey: .key("useTools"))
        try container.encode(useKnowledgeBag, forKey: .key("useKnowledgeBag"))
        try container.encode(useWebSearch, forKey: .key("useWebSearch"))
        try container.encode(reasoningEnabled, forKey: .key("reasoningEnabled"))
        try container.encode(reasoningEffortTier, forKey: .key("reasoningEffortTier"))
    }

    static let fallback = ChatComposerStartupPreferences(
        memberProfileEnabled: false,
        useTools: true,
        useKnowledgeBag: false,
        useWebSearch: false,
        reasoningEnabled: false,
        reasoningEffortTier: 1
    )

    static var `default`: ChatComposerStartupPreferences {
        fallback
    }
}
