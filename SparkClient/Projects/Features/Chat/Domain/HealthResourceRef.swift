import Foundation

/// Composer 草稿与健康资料预览条使用的引用（含 UI 快照；落库时仅三元组进入 block）。
struct HealthResourceRef: Equatable, Sendable, Identifiable, Codable {
    let identity: HealthResourceIdentity
    var displayTitle: String
    var displaySubtitle: String
    var typeBadge: String?

    var resourceType: String { identity.resourceType }
    var resourceID: Int { identity.resourceID }
    var memberID: Int { identity.memberID }

    var id: String { identity.cacheKey }
    init(
        identity: HealthResourceIdentity,
        displayTitle: String,
        displaySubtitle: String,
        typeBadge: String? = nil
    ) {
        self.identity = identity
        self.displayTitle = displayTitle
        self.displaySubtitle = displaySubtitle
        self.typeBadge = typeBadge
    }

    init(
        resourceType: String,
        resourceID: Int,
        memberID: Int,
        displayTitle: String,
        displaySubtitle: String,
        typeBadge: String? = nil
    ) {
        self.init(
            identity: HealthResourceIdentity(resourceType: resourceType, resourceID: resourceID, memberID: memberID),
            displayTitle: displayTitle,
            displaySubtitle: displaySubtitle,
            typeBadge: typeBadge
        )
    }

    init(
        type: HealthResourceType,
        resourceID: Int,
        memberID: Int,
        displayTitle: String,
        displaySubtitle: String,
        typeBadge: String? = nil
    ) {
        self.init(
            identity: HealthResourceIdentity(type: type, resourceID: resourceID, memberID: memberID),
            displayTitle: displayTitle,
            displaySubtitle: displaySubtitle,
            typeBadge: typeBadge
        )
    }

    var typedResource: HealthResourceType? {
        HealthResourceType(rawValue: resourceType)
    }

    func toMessagePayload(refIndex: Int) -> ChatHealthResourceReferencePayload {
        ChatHealthResourceReferencePayload(identity: identity, refIndex: refIndex)
    }
}

extension HealthResourceIdentity {
    init(_ ref: HealthResourceRef) {
        self = ref.identity
    }
}
