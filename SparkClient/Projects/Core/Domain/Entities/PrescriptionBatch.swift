import Foundation

struct PrescriptionBatch: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var medicalCaseID: Int?
    var prescriberName: String
    var institutionName: String
    var prescribedAt: Date?
    var diagnosis: String
    var batchNo: String
    var status: String
    var auditorName: String
    var auditedAt: Date?
    var extra: [String: String]
    var updatedAt: Date
}
