import Foundation

/// 消息块持久化载荷：仅三元组 + 展示顺序索引（与需求 §7 / 同步 JSON 对齐）。
nonisolated struct ChatHealthResourceReferencePayload: Codable, Equatable, Sendable {
    static let blockType = "health_resource_reference"

    let type: String
    let resourceType: String
    let resourceId: Int
    let memberId: Int
    let refIndex: Int

    init(
        resourceType: String,
        resourceId: Int,
        memberId: Int,
        refIndex: Int
    ) {
        self.type = Self.blockType
        self.resourceType = resourceType
        self.resourceId = resourceId
        self.memberId = memberId
        self.refIndex = refIndex
    }
}
