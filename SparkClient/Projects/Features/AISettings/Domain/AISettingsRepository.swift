import Foundation

protocol AISettingsRepository: Sendable {
    /// - Parameter ownerAccountID: 登录引导等场景传入当前会话账号，保证与 `UserSession` 一致；`nil` 时从 `SessionSnapshotStore` 解析。
    /// 目录数据以该账号本地 Core Data 为准；bundle 种子仅在首次初始化时写入一次。
    func loadSnapshot(ownerAccountID: Int64?) async -> AISettingsSnapshot
    func save(snapshot: AISettingsSnapshot) async throws
    /// 单条更新模型目录（按 `id` upsert）。
    func saveModel(_ model: AllModels) async throws
    /// 单条更新厂商配置（按 `id` upsert）。
    func saveProvider(_ provider: APIKeys) async throws
}

extension AISettingsRepository {
    func loadSnapshot() async -> AISettingsSnapshot {
        await loadSnapshot(ownerAccountID: nil)
    }
}
