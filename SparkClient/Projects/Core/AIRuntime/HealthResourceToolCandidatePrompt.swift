import Foundation

/// M11：健康资料工具候选确认 Sheet 载荷（不入库，走 `ToolInteractionCoordinator` 队列）。
nonisolated struct HealthResourceToolCandidatePrompt: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let threadID: UUID
    let candidates: [HealthResourceToolCandidateDTO]
    let maxSelectable: Int

    init(
        id: UUID = UUID(),
        threadID: UUID,
        candidates: [HealthResourceToolCandidateDTO],
        maxSelectable: Int = HealthResourceSendValidator.maxRefs
    ) {
        self.id = id
        self.threadID = threadID
        self.candidates = candidates
        self.maxSelectable = max(1, maxSelectable)
    }
}
