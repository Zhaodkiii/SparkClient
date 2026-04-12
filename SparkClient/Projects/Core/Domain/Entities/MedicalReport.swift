import Foundation

struct MedicalReport: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var medicalCaseID: Int?
    var category: String
    var title: String
    var hospital: String
    var doctor: String
    var content: String
    var date: Date
    var updatedAt: Date

    init(
        id: Int,
        memberID: Int,
        medicalCaseID: Int? = nil,
        category: String = "",
        title: String,
        hospital: String = "",
        doctor: String = "",
        content: String = "",
        date: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.memberID = memberID
        self.medicalCaseID = medicalCaseID
        self.category = category
        self.title = title
        self.hospital = hospital
        self.doctor = doctor
        self.content = content
        self.date = date
        self.updatedAt = updatedAt
    }
}
