import Foundation

struct MedicalCase: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var remoteID: Int?
    var memberID: UUID
    var title: String
    var chiefComplaint: String
    var diagnosis: String
    var severity: String
    var visitDate: Date
    var status: String
    var notes: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        remoteID: Int? = nil,
        memberID: UUID,
        title: String,
        chiefComplaint: String = "",
        diagnosis: String = "",
        severity: String = "unknown",
        visitDate: Date = Date(),
        status: String = "",
        notes: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.remoteID = remoteID
        self.memberID = memberID
        self.title = title
        self.chiefComplaint = chiefComplaint
        self.diagnosis = diagnosis
        self.severity = severity
        self.visitDate = visitDate
        self.status = status
        self.notes = notes
        self.updatedAt = updatedAt
    }
}
