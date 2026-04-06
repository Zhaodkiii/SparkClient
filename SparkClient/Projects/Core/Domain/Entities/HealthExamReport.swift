import Foundation

struct HealthExamReport: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var institutionName: String
    var reportNo: String
    var examDate: Date?
    var examType: Int
    var summary: String?
    var source: Int
    var rawOCR: [String: String]?
    var status: Int
    var extra: [String: String]?
    var updatedAt: Date
}
