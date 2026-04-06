import Foundation

struct MedicalRecord: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    let patientID: Int
    let title: String
    let summary: String
    let occurredAt: Date
    let updatedAt: Date

    init(
        id: Int,
        patientID: Int,
        title: String,
        summary: String,
        occurredAt: Date,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.patientID = patientID
        self.title = title
        self.summary = summary
        self.occurredAt = occurredAt
        self.updatedAt = updatedAt
    }
}
