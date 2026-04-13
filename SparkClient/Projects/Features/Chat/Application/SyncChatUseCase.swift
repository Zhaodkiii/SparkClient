import Foundation

struct SyncChatUseCase: Sendable {
    let syncEngine: ChatSyncEngine

    func execute() async throws {
        // 该入口用于“聊天页手动下拉刷新”，需要支持拉取远端未同步会话与消息。
        try await syncEngine.syncNowWithPull()
    }

    func syncThreadOnOpen(threadID: UUID) async throws {
        try await syncEngine.syncThreadOnOpen(threadID: threadID)
    }

    func startRealtime() async {
        await syncEngine.startRealtimeSync()
    }

    func stopRealtime() async {
        await syncEngine.stopRealtimeSync()
    }
}
