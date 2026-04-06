import Foundation

struct MedExamDetail: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var businessType: String
    var businessID: Int
    var memberID: Int
    var category: String
    var subCategory: String
    var itemName: String
    var itemCode: String
    var resultValue: String
    var unit: String
    var referenceRange: String
    var flag: String
    var resultAt: Date?
    var modality: String
    var bodyPart: String
    var diagnosis: String?
    var extra: [String: String]?
    var sortOrder: Int
    var updatedAt: Date
}
