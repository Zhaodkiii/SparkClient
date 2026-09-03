import Foundation

/// CHAT-000057 D-011/D-012：医疗类会话「从消息列表移除」的账号级可见性偏好。
///
/// 严格语义：只改变当前患者账号在消息列表中的可见性——
/// 不删除服务端 Thread、不删除消息/病历/审计记录、不调用 deleteThreadUseCase、
/// 不写 ChatThread.isDeleted；新患者可见消息到达后自动恢复。
struct ConversationListVisibilityPreference: Codable, Equatable, Sendable {
    let threadID: UUID
    var isHidden: Bool
    var hiddenAt: Date?
    var updatedAt: Date

    nonisolated init(threadID: UUID, isHidden: Bool, hiddenAt: Date?, updatedAt: Date = Date()) {
        self.threadID = threadID
        self.isHidden = isHidden
        self.hiddenAt = hiddenAt
        self.updatedAt = updatedAt
    }
}
