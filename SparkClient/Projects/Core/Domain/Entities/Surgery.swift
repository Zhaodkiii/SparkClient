import Foundation

/// 病历主档下的手术/操作记录，包含术式与质控字段。
struct Surgery: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var medicalCaseID: Int
    var procedureName: String
    var procedureCode: String
    var site: String
    var performedAt: Date?
    var surgeon: String
    var anesthesiaType: String
    var incisionLevel: String
    var asaClass: String
    var sourceSystemID: String
    var notes: String
    var extra: [String: String]
    var updatedAt: Date
}
