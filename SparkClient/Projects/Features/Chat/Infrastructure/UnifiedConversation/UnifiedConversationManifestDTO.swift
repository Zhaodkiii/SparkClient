import Foundation

/// CHAT-000057 29.3/30.3：统一消息会话 Manifest 远端 DTO。
/// 与服务端契约对齐：snake_case 由 JSONDecoder.chatRemote 转换；字段缺失时容忍旧服务端。
nonisolated struct UnifiedConversationManifestPageDTO: Codable, Sendable {
    let schemaVersion: Int
    let syncMode: String?
    let snapshotId: String?
    let nextCursor: String?
    let hasMore: Bool
    let resetRequired: Bool?
    let changes: [UnifiedConversationManifestChangeDTO]
}

nonisolated struct UnifiedConversationManifestChangeDTO: Codable, Sendable {
    /// upsert / delete
    let op: String
    let threadId: UUID
    let conversationKind: String?
    let memberId: Int?
    let serviceStatus: String?
    let identity: UnifiedConversationIdentityDTO?
    let bindingRevision: Int64
    /// delete 必填：permission_revoked / service_removed / binding_deleted / thread_deleted
    let reason: String?
    let updatedAt: Date?
}

nonisolated struct UnifiedConversationIdentityDTO: Codable, Sendable {
    let hospitalId: UUID?
    let doctorId: UUID?
    let agentId: UUID?
    let doctorDisplayName: String?
    let agentDisplayName: String?
    let departmentDisplayName: String?
    let hospitalDisplayName: String?
    let doctorAvatarUrl: String?
    let consultationId: UUID?
    let consultationDisplayName: String?
}

/// Manifest 解析/校验错误：受控失败，绝不回退为普通 AI。
enum UnifiedConversationManifestValidationError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidOperation(String)
    case missingKind(UUID)
    case invalidHospitalIdentity(UUID)
    case missingDeleteReason(UUID)
    case revisionRegression(UUID)
}
