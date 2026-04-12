import Foundation

struct ExaminationReportServerMutationService: Sendable {
    let resources: SparkMedicalWorkflowAPI

    func updateReport(
        report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments,
        draft: MedicalReportRecognitionDraft
    ) async throws {
        let updatePayload = ExaminationReportUpdatePayload(
            member: report.member,
            medicalRecord: report.medicalRecord,
            category: draft.category ?? "medical_report",
            subCategory: "",
            itemName: draft.title,
            performedAt: draft.date,
            reportedAt: draft.date,
            organizationName: draft.hospital,
            departmentName: report.departmentName ?? "",
            doctorName: draft.doctor ?? "",
            findings: draft.content,
            impression: draft.content,
            source: report.source ?? 2,
            rawOCR: ["text": draft.content],
            status: report.status ?? 1,
            extra: report.extra ?? [:]
        )

        _ = try await resources.update(
            SparkMedicalSyncAPI.RemoteExaminationReport.self,
            kind: .examinationReports,
            id: report.id,
            body: updatePayload
        )

        let existingDetails = try await resources.list(
            [SparkMedicalSyncAPI.RemoteMedExamDetail].self,
            kind: .medExamDetails,
            query: [
                URLQueryItem(name: "member_id", value: "\(report.member)"),
                URLQueryItem(name: "business_id", value: "\(report.id)")
            ]
        )

        for row in existingDetails where row.businessType.lowercased() == "examination_report" || row.businessType.lowercased() == "examination" {
            try await resources.delete(kind: .medExamDetails, id: row.id)
        }

        for (index, row) in draft.details.enumerated() {
            let detailPayload = MedExamDetailCreatePayload(
                businessType: "examination_report",
                businessID: report.id,
                member: report.member,
                category: row.category,
                subCategory: row.subCategory ?? "",
                itemName: row.itemName ?? "",
                itemCode: row.itemCode ?? "",
                resultValue: row.resultValue ?? "",
                unit: row.unit ?? "",
                referenceRange: row.referenceRange ?? "",
                flag: row.flag ?? "",
                resultAt: row.resultAt,
                modality: row.modality ?? "",
                bodyPart: row.bodyPart ?? "",
                diagnosis: row.diagnosis ?? "",
                extra: row.extra ?? [:],
                sortOrder: row.sortOrder.parsedAsSortOrderInt() ?? index
            )
            _ = try await resources.create(
                SparkMedicalSyncAPI.RemoteMedExamDetail.self,
                kind: .medExamDetails,
                body: detailPayload
            )
        }
    }

    func deleteReport(reportID: Int) async throws {
        try await resources.delete(kind: .examinationReports, id: reportID)
    }
}

private struct ExaminationReportUpdatePayload: Encodable {
    let member: Int
    let medicalRecord: Int?
    let category: String
    let subCategory: String
    let itemName: String
    let performedAt: String?
    let reportedAt: String?
    let organizationName: String?
    let departmentName: String
    let doctorName: String
    let findings: String
    let impression: String
    let source: Int
    let rawOCR: [String: String]
    let status: Int
    let extra: [String: String]

    enum CodingKeys: String, CodingKey {
        case member
        case medicalRecord = "medical_record"
        case category
        case subCategory = "sub_category"
        case itemName = "item_name"
        case performedAt = "performed_at"
        case reportedAt = "reported_at"
        case organizationName = "organization_name"
        case departmentName = "department_name"
        case doctorName = "doctor_name"
        case findings
        case impression
        case source
        case rawOCR = "raw_ocr"
        case status
        case extra
    }
}

private struct MedExamDetailCreatePayload: Encodable {
    let businessType: String
    let businessID: Int
    let member: Int
    let category: String
    let subCategory: String
    let itemName: String
    let itemCode: String
    let resultValue: String
    let unit: String
    let referenceRange: String
    let flag: String
    let resultAt: String?
    let modality: String
    let bodyPart: String
    let diagnosis: String
    let extra: [String: String]
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case businessType = "business_type"
        case businessID = "business_id"
        case member
        case category
        case subCategory = "sub_category"
        case itemName = "item_name"
        case itemCode = "item_code"
        case resultValue = "result_value"
        case unit
        case referenceRange = "reference_range"
        case flag
        case resultAt = "result_at"
        case modality
        case bodyPart = "body_part"
        case diagnosis
        case extra
        case sortOrder = "sort_order"
    }
}
