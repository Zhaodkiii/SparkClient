import Foundation

/// 病历主档下的症状条目，承载起病时间与持续时间等叙事信息。
struct Symptom: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var medicalCaseID: Int
    var name: String
    var code: String
    var severity: String
    var startedAt: Date?
    var durationValue: Int?
    var durationUnit: String
    var bodyPart: String
    var notes: String
    var extra: [String: String]
    var updatedAt: Date
}
