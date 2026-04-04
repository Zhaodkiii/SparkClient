import Foundation

struct SyncChatUseCase: Sendable {
    let syncEngine: ChatSyncEngine

    func execute() async throws {
        try await syncEngine.syncNow()
    }

    func startRealtime() async {
        await syncEngine.startRealtimeSync()
    }

    func stopRealtime() async {
        await syncEngine.stopRealtimeSync()
    }
}
