import Foundation

struct DeleteThreadUseCase: Sendable {
    let repository: any ChatRepository
    let syncEngine: ChatSyncEngine

    func execute(threadID: UUID) async {
        await repository.softDeleteThread(id: threadID)
        do {
            try await syncEngine.pushOutboxOnly()
        } catch {
            // 软删除以本地为准；服务端删除事件失败时保留待重试标记。
        }
    }
}
