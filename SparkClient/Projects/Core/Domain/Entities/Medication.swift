import Foundation

struct Medication: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var batchID: Int
    var genericName: String
    var brandName: String
    var drugName: String
    var dosageForm: String
    var strength: String
    var route: String
    var dosePerTime: String
    var doseValue: Double?
    var doseUnit: String
    var frequencyCode: String
    var period: String
    var timesPerPeriod: Int?
    var frequencyText: String
    var durationDays: Int?
    var instructions: String
    var reminderEnabled: Bool
    var reminderTimes: [String]
    var sortOrder: Int
    var extra: [String: String]
    var updatedAt: Date
}
