import Foundation

/// 单次 DeepTutor 生成会话：持有取消令牌、assistant 消息 ID 与节流落库状态。
actor DeepTutorGenerationSession {
    let operationID = UUID()
    let cancellationToken = AIRuntimeCancellationToken()

    private(set) var assistantMessageID: UUID?
    private(set) var isCancelled = false
    private var lastUIFlushAt = Date.distantPast
    private var lastDBFlushAt = Date.distantPast

    let uiFlushInterval: TimeInterval = 0.12
    let dbFlushInterval: TimeInterval = 0.5

    func bindAssistantMessageID(_ id: UUID) {
        assistantMessageID = id
    }

    func cancel() {
        isCancelled = true
        cancellationToken.cancel()
    }

    func shouldFlushUI(force: Bool = false) -> Bool {
        guard force == false else { return true }
        let now = Date()
        guard now.timeIntervalSince(lastUIFlushAt) >= uiFlushInterval else { return false }
        lastUIFlushAt = now
        return true
    }

    func shouldFlushDatabase(force: Bool = false) -> Bool {
        guard force == false else {
            lastDBFlushAt = Date()
            return true
        }
        let now = Date()
        guard now.timeIntervalSince(lastDBFlushAt) >= dbFlushInterval else { return false }
        lastDBFlushAt = now
        return true
    }

    func markDatabaseFlushed() {
        lastDBFlushAt = Date()
    }
}
