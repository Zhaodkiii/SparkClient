import Foundation

/// 聊天内健康资料详情导航值（包装 canonical identity）。
struct HealthResourceReference: Hashable, Sendable {
    let identity: HealthResourceIdentity

    var resourceType: String { identity.resourceType }
    var resourceID: Int { identity.resourceID }
    var memberID: Int { identity.memberID }
    var cacheKey: String { identity.cacheKey }

    init(identity: HealthResourceIdentity) {
        self.identity = identity
    }

    init(resourceType: String, resourceID: Int, memberID: Int) {
        self.init(identity: HealthResourceIdentity(resourceType: resourceType, resourceID: resourceID, memberID: memberID))
    }

    init(_ ref: HealthResourceRef) {
        self.init(identity: ref.identity)
    }

    init(_ payload: ChatHealthResourceReferencePayload) {
        self.init(identity: payload.identity)
    }

    var healthRef: HealthResourceRef {
        HealthResourceRef(
            identity: identity,
            displayTitle: "",
            displaySubtitle: ""
        )
    }
}

extension HealthResourceIdentity {
    init(_ reference: HealthResourceReference) {
        self = reference.identity
    }
}
