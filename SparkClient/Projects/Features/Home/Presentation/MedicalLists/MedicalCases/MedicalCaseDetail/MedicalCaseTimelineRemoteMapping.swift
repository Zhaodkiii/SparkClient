import Foundation

// MARK: - Remote → recognition drafts (timeline edit)

enum MedicalCaseTimelineRemoteMapping {
    static func examinationDraft(from report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> MedicalReportRecognitionDraft {
        let details = (report.medExamDetails ?? []).map { detail in
            ItemDraft(medicalReportItem: MedicalReportItem(
                category: detail.category ?? "",
                subCategory: detail.subCategory,
                itemName: detail.itemName,
                itemCode: detail.itemCode,
                resultValue: detail.resultValue,
                unit: detail.unit,
                referenceRange: detail.referenceRange,
                flag: detail.flag,
                resultAt: dateString(detail.resultAt),
                modality: detail.modality,
                bodyPart: detail.bodyPart,
                diagnosis: detail.diagnosis,
                extra: detail.extra,
                sortOrder: String(detail.sortOrder ?? 0)
            ))
        }

        return MedicalReportRecognitionDraft(
            category: report.category,
            title: report.itemName ?? "",
            hospital: report.organizationName,
            doctor: report.doctorName,
            content: report.impression ?? report.findings ?? "",
            date: dateString(report.reportedAt ?? report.performedAt),
            details: details
        )
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dateString(_ date: Date?) -> String {
        guard let date else { return "" }
        return dateFormatter.string(from: date)
    }

    static func symptomDraft(from row: SparkMedicalSyncAPI.RemoteSymptom) -> SymptomRecognitionDraft {
        SymptomRecognitionDraft(
            name: row.name,
            code: row.code.nilIfBlank,
            severity: row.severity.nilIfBlank,
            startedAt: row.startedAt.map { MedicalDateCoding.encodeDateOnly($0) },
            durationValue: row.durationValue.map { String($0) },
            durationUnit: row.durationUnit.nilIfBlank,
            bodyPart: row.bodyPart.nilIfBlank,
            notes: row.notes.nilIfBlank
        )
    }

    static func visitDraft(from row: SparkMedicalSyncAPI.RemoteVisit) -> VisitRecognitionDraft {
        VisitRecognitionDraft(
            visitType: row.visitType.nilIfBlank,
            visitedAt: row.visitedAt.map { MedicalDateCoding.encodeDateOnly($0) },
            department: row.department.nilIfBlank,
            doctorName: row.doctorName.nilIfBlank,
            visitNo: row.visitNo.nilIfBlank,
            notes: row.notes.nilIfBlank
        )
    }

    static func surgeryDraft(from row: SparkMedicalSyncAPI.RemoteSurgery) -> SurgeryRecognitionDraft {
        SurgeryRecognitionDraft(
            procedureName: row.procedureName,
            procedureCode: row.procedureCode.nilIfBlank,
            site: row.site.nilIfBlank,
            performedAt: row.performedAt.map { MedicalDateCoding.encodeDateOnly($0) },
            surgeon: row.surgeon.nilIfBlank,
            anesthesiaType: row.anesthesiaType.nilIfBlank,
            incisionLevel: row.incisionLevel.nilIfBlank,
            asaClass: row.asaClass.nilIfBlank,
            notes: row.notes.nilIfBlank
        )
    }

    static func followUpDraft(from row: SparkMedicalSyncAPI.RemoteFollowUp) -> FollowUpRecognitionDraft {
        FollowUpRecognitionDraft(
            plannedAt: row.plannedAt.map { MedicalDateCoding.encodeDateOnly($0) },
            completedAt: row.completedAt.map { MedicalDateCoding.encodeDateOnly($0) },
            status: row.status.nilIfBlank,
            method: row.method.nilIfBlank,
            outcome: row.outcome.nilIfBlank,
            nextAction: row.nextAction.nilIfBlank
        )
    }
}
