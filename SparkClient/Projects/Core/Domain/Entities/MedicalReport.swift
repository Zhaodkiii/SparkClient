import Foundation

struct MedicalReport: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var remoteID: Int?
    var memberID: UUID
    var medicalCaseID: UUID?
    var reportType: String
    var title: String
    var hospital: String
    var doctor: String
    var content: String
    var date: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        remoteID: Int? = nil,
        memberID: UUID,
        medicalCaseID: UUID? = nil,
        reportType: String = "",
        title: String,
        hospital: String = "",
        doctor: String = "",
        content: String = "",
        date: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.remoteID = remoteID
        self.memberID = memberID
        self.medicalCaseID = medicalCaseID
        self.reportType = reportType
        self.title = title
        self.hospital = hospital
        self.doctor = doctor
        self.content = content
        self.date = date
        self.updatedAt = updatedAt
    }
}
