import Foundation

/// 病历主档下的随访记录，覆盖计划、执行与下一步建议。
struct FollowUp: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var medicalCaseID: Int
    var plannedAt: Date?
    var completedAt: Date?
    var status: String
    var method: String
    var outcome: String
    var nextAction: String
    var extra: [String: String]
    var updatedAt: Date
}
