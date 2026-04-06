import Foundation

struct Prescription: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    var medicalCaseID: Int?
    var drugName: String
    var dosage: String
    var frequency: String
    var durationDays: Int
    var instructions: String
    var startDate: Date?
    var endDate: Date?
    var status: String
    var updatedAt: Date

    init(
        id: Int,
        memberID: Int,
        medicalCaseID: Int? = nil,
        drugName: String,
        dosage: String = "",
        frequency: String = "",
        durationDays: Int = 0,
        instructions: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        status: String = "active",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.memberID = memberID
        self.medicalCaseID = medicalCaseID
        self.drugName = drugName
        self.dosage = dosage
        self.frequency = frequency
        self.durationDays = durationDays
        self.instructions = instructions
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.updatedAt = updatedAt
    }
}
