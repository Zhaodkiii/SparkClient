import Foundation

/// 健康资料 canonical 身份（草稿、消息、导航、工具 DTO 均围绕此值对象）。
struct HealthResourceIdentity: Hashable, Codable, Sendable {
    let resourceType: String
    let resourceID: Int
    let memberID: Int

    init(resourceType: String, resourceID: Int, memberID: Int) {
        self.resourceType = resourceType
        self.resourceID = resourceID
        self.memberID = memberID
    }

    init(type: HealthResourceType, resourceID: Int, memberID: Int) {
        self.init(resourceType: type.rawValue, resourceID: resourceID, memberID: memberID)
    }

    var typedResource: HealthResourceType? {
        HealthResourceType(rawValue: resourceType)
    }

    var cacheKey: String {
        "\(resourceType):\(resourceID):\(memberID)"
    }
}
