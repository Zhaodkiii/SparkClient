import Foundation

/// 聊天内健康资料详情导航值（与消息 block 三元组一致，供 `NavigationLink` / `navigationDestination`）。
struct HealthResourceReference: Hashable, Sendable {
    let resourceType: String
    let resourceID: Int
    let memberID: Int

    init(resourceType: String, resourceID: Int, memberID: Int) {
        self.resourceType = resourceType
        self.resourceID = resourceID
        self.memberID = memberID
    }

    init(_ ref: HealthResourceRef) {
        self.init(resourceType: ref.resourceType, resourceID: ref.resourceID, memberID: ref.memberID)
    }

    init(_ payload: ChatHealthResourceReferencePayload) {
        self.init(
            resourceType: payload.resourceType,
            resourceID: payload.resourceId,
            memberID: payload.memberId
        )
    }

    var cacheKey: String {
        "\(resourceType):\(resourceID):\(memberID)"
    }

    var healthRef: HealthResourceRef {
        HealthResourceRef(
            resourceType: resourceType,
            resourceID: resourceID,
            memberID: memberID,
            displayTitle: "",
            displaySubtitle: ""
        )
    }
}
