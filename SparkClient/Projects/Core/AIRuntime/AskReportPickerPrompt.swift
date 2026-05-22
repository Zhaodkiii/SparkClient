import Foundation

/// 手动「问报告」资料选择 Sheet 载荷（走 `ToolInteractionCoordinator` 统一队列）。
struct AskReportPickerPrompt: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let threadID: UUID
    let memberID: Int

    init(id: UUID = UUID(), threadID: UUID, memberID: Int) {
        self.id = id
        self.threadID = threadID
        self.memberID = memberID
    }
}
