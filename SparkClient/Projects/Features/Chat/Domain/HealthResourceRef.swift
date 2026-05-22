import Foundation

/// Composer 草稿与健康资料预览条使用的引用（含 UI 快照；落库时仅三元组进入 block）。
nonisolated struct HealthResourceRef: Equatable, Sendable, Identifiable, Codable {
    let resourceType: String
    let resourceID: Int
    let memberID: Int
    var displayTitle: String
    var displaySubtitle: String
    var typeBadge: String?

    var id: String { "\(resourceType):\(resourceID):\(memberID)" }

    init(
        resourceType: String,
        resourceID: Int,
        memberID: Int,
        displayTitle: String,
        displaySubtitle: String,
        typeBadge: String? = nil
    ) {
        self.resourceType = resourceType
        self.resourceID = resourceID
        self.memberID = memberID
        self.displayTitle = displayTitle
        self.displaySubtitle = displaySubtitle
        self.typeBadge = typeBadge
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
            resourceType: type.rawValue,
            resourceID: resourceID,
            memberID: memberID,
            displayTitle: displayTitle,
            displaySubtitle: displaySubtitle,
            typeBadge: typeBadge
        )
    }

    var typedResource: HealthResourceType? {
        HealthResourceType(rawValue: resourceType)
    }

    func toMessagePayload(refIndex: Int) -> ChatHealthResourceReferencePayload {
        ChatHealthResourceReferencePayload(
            resourceType: resourceType,
            resourceId: resourceID,
            memberId: memberID,
            refIndex: refIndex
        )
    }
}
