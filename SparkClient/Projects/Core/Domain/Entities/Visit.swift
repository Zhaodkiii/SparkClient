import Foundation

/// 病历主档下的就诊节点记录（首诊/复诊/急诊等）。
struct Visit: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var medicalCaseID: Int
    var visitType: String
    var visitedAt: Date?
    var department: String
    var doctorName: String
    var visitNo: String
    var sourceSystemID: String
    var notes: String
    var extra: [String: String]
    var updatedAt: Date
}
