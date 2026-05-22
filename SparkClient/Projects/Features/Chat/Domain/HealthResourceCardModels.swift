import Foundation

enum HealthResourceCardLoadStatus: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case notFound
    case failed(message: String)
}

struct HealthResourceCardSummary: Equatable, Sendable {
    let resourceType: String
    let resourceId: Int
    let memberId: Int
    let refIndex: Int
    let status: HealthResourceCardLoadStatus
    let typeLabel: String
    let title: String
    let dateText: String?
    let organizationText: String?
    let summaryText: String?
    let badgeTexts: [String]
    let attachmentCount: Int?
    let indexText: String

    var cacheKey: String {
        "\(resourceType):\(resourceId):\(memberId)"
    }
}
