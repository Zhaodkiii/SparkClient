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

    func pushSingleThread(threadID: UUID) async throws {
        try await supervisor.pushSingleThread(threadID: threadID)
    }

    func startRealtime() async {
        await supervisor.startRealtimeSync()
    }

    func stopRealtime() async {
        await supervisor.stopRealtimeSync()
    }
}
