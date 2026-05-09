import Foundation

struct Prescription: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var medicalCaseID: Int?
    var prescriberName: String
    var institutionName: String
    var prescribedAt: Date?
    var diagnosis: String
    var prescriptionNo: String?
    var status: String
    var extra: [String: String]
    var updatedAt: Date
}
