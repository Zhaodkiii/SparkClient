import Foundation

/// 并发动作互斥器：
/// 避免多 Task 同时写同一条消息状态时出现竞态（重复请求、状态错乱）。
actor ChatMessageActionState {
    private var translatingMessageIDs: Set<UUID> = []
    private var savingMessageIDs: Set<UUID> = []
    private var savingKnowledgeCardIDs: Set<UUID> = []
    private var loadingTaskCardIDs: Set<Int> = []

    func beginTranslating(_ id: UUID) -> Bool { translatingMessageIDs.insert(id).inserted }
    func endTranslating(_ id: UUID) { translatingMessageIDs.remove(id) }

    func beginSavingMessage(_ id: UUID) -> Bool { savingMessageIDs.insert(id).inserted }
    func endSavingMessage(_ id: UUID) { savingMessageIDs.remove(id) }

    func beginSavingKnowledgeCard(_ id: UUID) -> Bool { savingKnowledgeCardIDs.insert(id).inserted }
    func endSavingKnowledgeCard(_ id: UUID) { savingKnowledgeCardIDs.remove(id) }

    func beginTaskCardLoading(_ id: Int) -> Bool { loadingTaskCardIDs.insert(id).inserted }
    func endTaskCardLoading(_ id: Int) { loadingTaskCardIDs.remove(id) }
}

/// 流式回包滚动节流器：
/// 仅在 generation 达到最小步长时触发滚动，避免高频抖动。
actor ChatScrollThrottler {
    private var lastGeneration: UInt64 = 0
    private let minGenerationStep: UInt64

    init(minGenerationStep: UInt64) {
        self.minGenerationStep = minGenerationStep
    }

    func shouldScroll(generation: UInt64) -> Bool {
        guard generation >= lastGeneration + minGenerationStep else { return false }
        lastGeneration = generation
        return true
    }
}
