import Foundation

struct ChatHealthResourcePreviewDetailRow: Identifiable, Equatable, Sendable {
    let id: Int
    let itemName: String
    let resultLine: String
    let flag: String
    let isFlagged: Bool
}

struct ChatHealthResourcePreviewDetailGroup: Identifiable, Equatable, Sendable {
    let id: String
    let category: String
    let rows: [ChatHealthResourcePreviewDetailRow]
}

struct ChatHealthResourcePreviewContent: Equatable, Sendable {
    let memberName: String?
    let typeLabel: String
    let categoryBadge: String?
    let examinationCategory: ExaminationReportCategory?
    let title: String
    let dateText: String?
    let organizationText: String?
    let summaryText: String?
    let findingsText: String?
    let impressionText: String?
    let extraLines: [String]
    let detailGroups: [ChatHealthResourcePreviewDetailGroup]
    let attachments: [SparkMedicalSyncAPI.RemoteManagedFile]
}
