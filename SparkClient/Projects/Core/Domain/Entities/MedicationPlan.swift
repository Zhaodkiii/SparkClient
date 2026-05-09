import Foundation

struct MedicationPlan: Identifiable, Codable, Equatable, Sendable {
    struct ReminderTime: Codable, Equatable, Sendable {
        var time: String
        var dose: Double?
    }

    let id: Int
    var memberID: Int
    var medicalCaseID: Int?
    var medicineBoxID: Int?
    var prescriptionID: Int?
    var drugName: String
    var dosePerTime: String
    var doseValue: Double?
    var doseUnit: String
    var frequencyText: String
    var frequencyCode: String
    var reminderTimes: [ReminderTime]
    var startDate: Date
    var endDate: Date?
    var durationDays: Int?
    var instructions: String
    var reminderEnabled: Bool
    var status: String
    var extra: [String: String]
    var updatedAt: Date
}
