import Foundation

struct DefaultTypedMedicalDocumentSaver: TypedMedicalDocumentSaving, Sendable {
    let workflowAPI: SparkMedicalWorkflowAPI
    let logger: Logger

    init(
        workflowAPI: SparkMedicalWorkflowAPI,
        logger: Logger = ConsoleLogger()
    ) {
        self.workflowAPI = workflowAPI
        self.logger = logger
    }

    func save(output: MedicalDocumentTypedExtractionOutput) async throws -> MedicalDocumentSaveReceipt {
        let memberID = output.envelope.memberID
        let now = Date()
        let recordID: Int

        switch output.typedResult {
        case .caseDocument(let draft):
            recordID = try await workflowAPI.saveCase(
                .init(
                    member: memberID,
                    recordType: "case_document",
                    status: 2,
                    title: draft.title,
                    diagnosisSummary: draft.diagnosis ?? draft.summary,
                    extra: ["source": "typed_upload"]
                )
            )
        case .healthExamReport(let draft):
            let payload = buildHealthExamPayload(
                memberID: memberID,
                draft: draft,
                rawOCRText: output.envelope.rawOCRText,
                now: now
            )
            logger.debug(
                "体检保存请求准备完成，draftItems=\(draft.items.count), details=\(payload.details.count), reportNo=\(payload.reportNo), summaryLength=\(payload.summary?.count ?? 0)",
                category: "medical_upload"
            )
            recordID = try await workflowAPI.saveHealthExam(
                payload
            )
        case .medicalReport(let draft):
            let payload = buildMedicalReportPayload(memberID: memberID, draft: draft, now: now)
            recordID = try await workflowAPI.saveMedicalReport(
                payload
            )
        case .prescription(let draft):
            let medications = buildPrescriptionMedicationPayloads(
                memberID: memberID,
                draft: draft
            )
            recordID = try await workflowAPI.savePrescription(
                .init(
                    member: memberID,
                    medicalCase: nil,
                    prescriberName: draft.prescriberName ?? "",
                    institutionName: draft.institutionName ?? "",
                    prescribedAt: (draft.prescribedAt ?? now).toISO8601(),
                    diagnosis: draft.diagnosis ?? "",
                    batchNo: draft.batchNo ?? "",
                    status: nil,
                    auditorName: "",
                    auditedAt: nil,
                    extra: ["source": "typed_upload"],
                    medications: medications
                )
            )
        case .medication(let draft):
            recordID = try await workflowAPI.saveMedication(
                .init(
                    member: memberID,
                    batch: 0,
                    genericName: draft.drugName,
                    brandName: "",
                    drugName: draft.drugName,
                    dosageForm: "",
                    strength: draft.dosage ?? "",
                    route: "",
                    dosePerTime: draft.dosage ?? "",
                    doseValue: nil,
                    doseUnit: "",
                    frequencyCode: "",
                    period: "",
                    timesPerPeriod: nil,
                    frequencyText: draft.frequencyText ?? "",
                    durationDays: draft.durationDays,
                    instructions: draft.instructions ?? "",
                    reminderEnabled: false,
                    reminderTimes: [],
                    sortOrder: 0,
                    extra: ["source": "typed_upload"]
                )
            )
        }
        logger.info("typed 结果保存完成，memberID=\(memberID)", category: "medical_upload")
        return MedicalDocumentSaveReceipt(recordID: recordID, savedAt: now, isSuccess: true)
    }
}

private extension Date {
    func toDateOnly() -> String { MedicalDateCoding.encodeDateOnly(self) }
    func toISO8601() -> String { MedicalDateCoding.encodeISO8601(self) }
}

private extension DefaultTypedMedicalDocumentSaver {
    func buildHealthExamPayload(
        memberID: Int,
        draft: HealthExamRecognitionDraft,
        rawOCRText: String,
        now: Date
    ) -> SparkMedicalWorkflowAPI.HealthExamSavePayload {
        let institutionName = resolvedHealthExamInstitutionName(draft: draft, rawOCRText: rawOCRText) ?? ""
        return .init(
            member: memberID,
            institutionName: institutionName,
            reportNo: draft.reportNo ?? "",
            examDate: (draft.examDate ?? now).toDateOnly(),
            examType: parseHealthExamType(draft.examType),
            summary: draft.summary,
            source: 2,
            rawOCR: ["text": rawOCRText],
            status: 1,
            extra: ["source": "typed_upload"],
            details: buildHealthExamDetails(draft: draft, defaultDate: (draft.examDate ?? now).toISO8601())
        )
    }

    func resolvedHealthExamInstitutionName(
        draft: HealthExamRecognitionDraft,
        rawOCRText: String
    ) -> String? {
        if let institutionName = draft.institutionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           institutionName.isEmpty == false {
            return institutionName
        }
        let lines = rawOCRText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && $0.hasPrefix("===") == false }
        let keywords = ["医院", "体检", "健康", "门诊", "中心", "clinic", "hospital", "health"]
        return lines.first { line in
            let normalized = line.lowercased()
            return keywords.contains { normalized.contains($0.lowercased()) }
        } ?? lines.first
    }

    func parseHealthExamType(_ rawValue: String?) -> Int {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              rawValue.isEmpty == false else {
            return 1
        }
        switch rawValue {
        case "1", "routine", "常规", "常规体检":
            return 1
        case "2", "onboarding", "入职", "入职体检":
            return 2
        case "3", "special", "专项", "专项体检":
            return 3
        case "4", "senior", "老年", "老年体检":
            return 4
        default:
            return 1
        }
    }

    func buildHealthExamDetails(
        draft: HealthExamRecognitionDraft,
        defaultDate: String
    ) -> [SparkMedicalWorkflowAPI.MedicalReportDetailPayload] {
        draft.items.enumerated().map { index, item in
            .init(
                category: item.category,
                subCategory: item.subCategory,
                itemName: item.itemName,
                itemCode: item.itemCode,
                resultValue: item.resultValue,
                unit: item.unit,
                referenceRange: item.referenceRange,
                flag: item.flag,
                resultAt: item.resultAt?.toISO8601() ?? defaultDate,
                modality: item.modality,
                bodyPart: item.bodyPart,
                diagnosis: item.diagnosis ?? "",
                extra: item.extra,
                sortOrder: item.sortOrder == 0 ? index : item.sortOrder
            )
        }
    }

    func buildPrescriptionMedicationPayloads(
        memberID: Int,
        draft: PrescriptionRecognitionDraft
    ) -> [SparkMedicalWorkflowAPI.MedicationSavePayload] {
        draft.medications.enumerated().map { index, item in
            SparkMedicalWorkflowAPI.MedicationSavePayload(
                member: memberID,
                batch: 0,
                genericName: item.name,
                brandName: "",
                drugName: item.name,
                dosageForm: "",
                strength: item.specification ?? "",
                route: "",
                dosePerTime: item.dosage ?? "",
                doseValue: nil,
                doseUnit: "",
                frequencyCode: "",
                period: "",
                timesPerPeriod: nil,
                frequencyText: item.frequency ?? "",
                durationDays: parseDurationDays(item.duration),
                instructions: item.instructions ?? "",
                reminderEnabled: false,
                reminderTimes: [],
                sortOrder: index,
                extra: ["source": "typed_upload"]
            )
        }
    }

    func parseDurationDays(_ durationText: String?) -> Int? {
        guard let durationText else { return nil }
        if let numeric = Int(durationText) { return numeric }
        let digits = durationText.filter(\.isNumber)
        return Int(digits)
    }

    func buildMedicalReportPayload(
        memberID: Int,
        draft: MedicalReportRecognitionDraft,
        now: Date
    ) -> SparkMedicalWorkflowAPI.MedicalReportSavePayload {
        let dateText = (draft.date ?? now).toISO8601()
        return .init(
            member: memberID,
            medicalCase: nil,
            reportType: draft.reportType ?? "medical_report",
            category: draft.reportType ?? "medical_report",
            subCategory: "",
            itemName: draft.title,
            performedAt: dateText,
            reportedAt: dateText,
            organizationName: draft.hospital,
            departmentName: "",
            doctorName: draft.doctor ?? "",
            findings: draft.content.isEmpty ? draft.title : draft.content,
            impression: draft.content.isEmpty ? draft.title : draft.content,
            modality: "",
            bodyPart: "",
            diagnosis: "",
            details: draft.details.enumerated().map { index, row in
                .init(
                    category: row.category,
                    subCategory: row.subCategory,
                    itemName: row.itemName,
                    itemCode: row.itemCode,
                    resultValue: row.resultValue,
                    unit: row.unit,
                    referenceRange: row.referenceRange,
                    flag: row.flag,
                    resultAt: row.resultAt?.toISO8601() ?? dateText,
                    modality: row.modality,
                    bodyPart: row.bodyPart,
                    diagnosis: row.diagnosis ?? "",
                    extra: row.extra,
                    sortOrder: row.sortOrder == 0 ? index : row.sortOrder
                )
            }
        )
    }
}
