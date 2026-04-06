import Foundation

struct ExaminationReport: Identifiable, Codable, Equatable, Sendable {
    enum Source: Int, Codable, Sendable {
        case manual = 1
        case ocr = 2
    }

    enum Status: Int, Codable, Sendable {
        case draft = 1
        case completed = 2
        case revised = 3
        case discarded = 4
    }

    let id: Int
    var memberID: Int
    var medicalRecordID: Int?
    var category: String
    var subCategory: String
    var itemName: String
    var performedAt: Date?
    var reportedAt: Date?
    var organizationName: String
    var departmentName: String
    var doctorName: String
    var findings: String?
    var impression: String?
    var source: Int
    var rawOCR: [String: String]?
    var status: Int
    var extra: [String: String]?
    var updatedAt: Date

    init(
        id: Int,
        memberID: Int,
        medicalRecordID: Int? = nil,
        category: String = "",
        subCategory: String = "",
        itemName: String,
        performedAt: Date? = nil,
        reportedAt: Date? = nil,
        organizationName: String,
        departmentName: String = "",
        doctorName: String = "",
        findings: String? = nil,
        impression: String? = nil,
        source: Int = 1,
        rawOCR: [String: String]? = nil,
        status: Int = 1,
        extra: [String: String]? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.memberID = memberID
        self.medicalRecordID = medicalRecordID
        self.category = category
        self.subCategory = subCategory
        self.itemName = itemName
        self.performedAt = performedAt
        self.reportedAt = reportedAt
        self.organizationName = organizationName
        self.departmentName = departmentName
        self.doctorName = doctorName
        self.findings = findings
        self.impression = impression
        self.source = source
        self.rawOCR = rawOCR
        self.status = status
        self.extra = extra
        self.updatedAt = updatedAt
    }
}
