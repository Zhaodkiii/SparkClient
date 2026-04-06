import Foundation

struct MedicalCase: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    var memberID: Int
    /// 病历类型：例如 outpatient/inpatient/custom。
    var recordType: String
    /// 状态：1 草稿，2 已提交，3 已归档。
    var status: Int
    var title: String
    var hospitalName: String
    var ageAtVisit: Int?
    var diagnosisSummary: String
    var extra: [String: String]
    var updatedAt: Date

    init(
        id: Int,
        memberID: Int,
        recordType: String = "custom",
        status: Int = 1,
        title: String,
        hospitalName: String = "",
        ageAtVisit: Int? = nil,
        diagnosisSummary: String = "",
        extra: [String: String] = [:],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.memberID = memberID
        self.recordType = recordType
        self.status = status
        self.title = title
        self.hospitalName = hospitalName
        self.ageAtVisit = ageAtVisit
        self.diagnosisSummary = diagnosisSummary
        self.extra = extra
        self.updatedAt = updatedAt
    }
}
