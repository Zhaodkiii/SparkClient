import Foundation

struct MedicalRecord: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    let memberID: Int
    let title: String
    let summary: String
    let occurredAt: Date
    let updatedAt: Date

    init(
        id: Int,
        memberID: Int,
        title: String,
        summary: String,
        occurredAt: Date,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.memberID = memberID
        self.title = title
        self.summary = summary
        self.occurredAt = occurredAt
        self.updatedAt = updatedAt
    }
}
