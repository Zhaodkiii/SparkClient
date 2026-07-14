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
    var severity: String?
    var caseStatus: String?
    var diagnosisSummary: String
    var extra: [String: String]
    var updatedAt: Date
    var isArchived: Bool
    var archivedAt: Date?

    init(
        id: Int,
        memberID: Int,
        recordType: String = "custom",
        status: Int = 1,
        title: String,
        hospitalName: String = "",
        ageAtVisit: Int? = nil,
        severity: String? = nil,
        caseStatus: String? = nil,
        diagnosisSummary: String = "",
        extra: [String: String] = [:],
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.memberID = memberID
        self.recordType = recordType
        self.status = status
        self.title = title
        self.hospitalName = hospitalName
        self.ageAtVisit = ageAtVisit
        self.severity = severity
        self.caseStatus = caseStatus
        self.diagnosisSummary = diagnosisSummary
        self.extra = extra
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
    }
}
