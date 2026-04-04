import Foundation

struct ExaminationReport: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var remoteID: Int?
    var memberID: UUID
    var medicalCaseID: UUID?
    var category: String
    var subcategory: String
    var reportName: String
    var checkType: String
    var conclusion: String
    var doctorAdvice: String
    var date: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        remoteID: Int? = nil,
        memberID: UUID,
        medicalCaseID: UUID? = nil,
        category: String = "",
        subcategory: String = "",
        reportName: String,
        checkType: String = "",
        conclusion: String = "",
        doctorAdvice: String = "",
        date: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.remoteID = remoteID
        self.memberID = memberID
        self.medicalCaseID = medicalCaseID
        self.category = category
        self.subcategory = subcategory
        self.reportName = reportName
        self.checkType = checkType
        self.conclusion = conclusion
        self.doctorAdvice = doctorAdvice
        self.date = date
        self.updatedAt = updatedAt
    }
}
