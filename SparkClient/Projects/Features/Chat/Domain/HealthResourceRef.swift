import Foundation

/// Composer 草稿与健康资料预览条使用的引用（含 UI 快照；落库时仅三元组进入 block）。
nonisolated struct HealthResourceRef: Equatable, Sendable, Identifiable, Codable {
    let identity: HealthResourceIdentity
    var displayTitle: String
    var displaySubtitle: String
    var typeBadge: String?

    nonisolated var resourceType: String { identity.resourceType }
    nonisolated var resourceID: Int { identity.resourceID }
    nonisolated var memberID: Int { identity.memberID }

    nonisolated var id: String { identity.cacheKey }
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

    nonisolated var typedResource: HealthResourceType? {
        HealthResourceType(rawValue: resourceType)
    }

    nonisolated func toMessagePayload(refIndex: Int) -> ChatHealthResourceReferencePayload {
        ChatHealthResourceReferencePayload(identity: identity, refIndex: refIndex)
    }
}

extension HealthResourceIdentity {
    nonisolated init(_ ref: HealthResourceRef) {
        self = ref.identity
    }
}
