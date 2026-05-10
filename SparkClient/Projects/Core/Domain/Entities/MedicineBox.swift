import Foundation

struct MedicineBox: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var medicineName: String
    var medicineType: String?
    var brandName: String
    var dosageForm: String
    var strength: String
    var doseUnit: String = ""
    var totalQuantity: Double?
    var expireDate: Date?
    var notes: String
    var extra: [String: String]
    var updatedAt: Date
}
