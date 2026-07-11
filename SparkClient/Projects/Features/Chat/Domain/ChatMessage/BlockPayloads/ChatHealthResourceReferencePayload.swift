import Foundation

/// 消息块持久化载荷：identity 三元组 + 展示顺序索引（JSON key 使用 snake_case）。
nonisolated struct ChatHealthResourceReferencePayload: Codable, Equatable, Sendable {
    static let blockType = "health_resource_reference"

    let type: String
    let resourceType: String
    let resourceId: Int
    let memberId: Int
    let refIndex: Int

    var identity: HealthResourceIdentity {
        HealthResourceIdentity(resourceType: resourceType, resourceID: resourceId, memberID: memberId)
    }

    init(identity: HealthResourceIdentity, refIndex: Int) {
        self.type = Self.blockType
        self.resourceType = identity.resourceType
        self.resourceId = identity.resourceID
        self.memberId = identity.memberID
        self.refIndex = refIndex
    }

    init(
        resourceType: String,
        resourceId: Int,
        memberId: Int,
        refIndex: Int
    ) {
        self.init(
            identity: HealthResourceIdentity(resourceType: resourceType, resourceID: resourceId, memberID: memberId),
            refIndex: refIndex
        )
    }
}

extension HealthResourceIdentity {
    init(_ payload: ChatHealthResourceReferencePayload) {
        self = payload.identity
    }
}
