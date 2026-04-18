import Foundation

/// 编排聊天同步子系统：REST/WebSocket 同步引擎 + 附件落盘管线，供生命周期与用例统一入口。
actor ChatSyncSupervisor {
    private let syncEngine: ChatSyncEngine
    private let attachmentPipeline: ChatAttachmentPipeline

    init(syncEngine: ChatSyncEngine, attachmentPipeline: ChatAttachmentPipeline) {
        self.syncEngine = syncEngine
        self.attachmentPipeline = attachmentPipeline
    }

    func syncNow() async throws {
        try await syncEngine.syncNow()
        await attachmentPipeline.processPendingJobs(limit: 8)
    }

    func syncNowWithPull() async throws {
        try await syncEngine.syncNowWithPull()
        await attachmentPipeline.processPendingJobs(limit: 24)
    }

    func syncThreadOnOpen(threadID: UUID) async throws {
        try await syncEngine.syncThreadOnOpen(threadID: threadID)
        await attachmentPipeline.processPendingJobs(limit: 16)
    }

    func pushOutboxOnly() async throws {
        try await syncEngine.pushOutboxOnly()
        await attachmentPipeline.processPendingJobs(limit: 8)
    }

    func startRealtimeSync() async {
        await syncEngine.startRealtimeSync()
    }

    func stopRealtimeSync() async {
        await syncEngine.stopRealtimeSync()
    }

    /// 登录/会话引导后可选调用：不阻塞 UI 地消化积压图片任务。
    func kickAttachmentDrain() async {
        await attachmentPipeline.processPendingJobs(limit: 32)
    }
}
