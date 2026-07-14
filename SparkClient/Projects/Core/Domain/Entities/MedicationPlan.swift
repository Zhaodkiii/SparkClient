import Foundation

struct MedicationPlan: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var medicalCaseID: Int?
    var medicineBoxID: Int?
    var prescriptionID: Int?
    var drugName: String
    var dosePerTime: String
    var doseValue: Double?
    var doseUnit: String
    var frequencyType: String
    var everyNDays: Int?
    var weeklyWeekdays: [Int]
    var frequencyText: String
    var reminderTimes: [ReminderTime]
    var startDate: Date
    var endDate: Date?
    var instructions: String
    var reminderEnabled: Bool
    var status: String
    var extra: [String: String]
    var updatedAt: Date
    var isArchived: Bool = false
    var archivedAt: Date?
}
