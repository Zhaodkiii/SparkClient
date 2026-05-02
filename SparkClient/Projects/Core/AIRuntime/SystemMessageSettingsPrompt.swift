import Foundation

/// 当前会话系统消息设置 Sheet 的展示载荷（不入库）。
struct SystemMessageSettingsPrompt: Codable, Equatable, Sendable {
    let id: UUID
    let threadID: UUID
    let sessionPrompt: String
    let defaultPrompt: String
    let modelDisplayName: String
    let isAgentModel: Bool
    let agentPrompt: String?

    init(
        id: UUID = UUID(),
        threadID: UUID,
        sessionPrompt: String,
        defaultPrompt: String,
        modelDisplayName: String,
        isAgentModel: Bool,
        agentPrompt: String?
    ) {
        self.id = id
        self.threadID = threadID
        self.sessionPrompt = sessionPrompt
        self.defaultPrompt = defaultPrompt
        self.modelDisplayName = modelDisplayName
        self.isAgentModel = isAgentModel
        self.agentPrompt = agentPrompt
    }
}
