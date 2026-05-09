import Foundation

struct MedicineBox: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var drugName: String
    var medicineType: String?
    var genericName: String
    var brandName: String
    var dosageForm: String
    var strength: String
    var totalQuantity: Double
    var remainingQuantity: Double
    var unit: String
    var expireDate: Date?
    var productionBatch: String
    var notes: String
    var extra: [String: String]
    var updatedAt: Date
}
