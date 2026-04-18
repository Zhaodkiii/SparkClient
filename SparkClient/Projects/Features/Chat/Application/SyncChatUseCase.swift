import Foundation

struct SyncChatUseCase: Sendable {
    let supervisor: ChatSyncSupervisor

    func execute() async throws {
        try await supervisor.syncNowWithPull()
    }

    func syncThreadOnOpen(threadID: UUID) async throws {
        try await supervisor.syncThreadOnOpen(threadID: threadID)
    }

    func pushOutboxOnly() async throws {
        try await supervisor.pushOutboxOnly()
    }

    func startRealtime() async {
        await supervisor.startRealtimeSync()
    }

    func stopRealtime() async {
        await supervisor.stopRealtimeSync()
    }
}
