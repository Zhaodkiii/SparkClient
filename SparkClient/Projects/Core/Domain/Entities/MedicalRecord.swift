import Foundation

struct MedicalRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let patientID: UUID
    let title: String
    let summary: String
    let occurredAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        patientID: UUID,
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
