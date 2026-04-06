import Foundation

struct MedicationTakenRecord: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var medicationID: Int
    var scheduledAt: Date
    var takenAt: Date?
    var status: String
    var doseSequence: Int
    var actualDose: String
    var timezone: String
    var notes: String
    var extra: [String: String]
    var updatedAt: Date
}
