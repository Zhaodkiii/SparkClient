import Foundation

struct SyncChatUseCase: Sendable {
    let syncEngine: ChatSyncEngine

    func execute() async throws {
        try await syncEngine.syncNow()
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
