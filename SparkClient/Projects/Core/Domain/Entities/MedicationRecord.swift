import Foundation

struct MedicationRecord: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var planID: Int
    var scheduledAt: Date
    var takenAt: Date?
    var status: String
    var plannedDose: String
    var actualDose: String
    var doseSequence: Int
    var timezone: String
    var notes: String
    var extra: [String: String]
    var updatedAt: Date
}
