import Foundation

// MARK: - Remote → recognition drafts (timeline edit)

enum MedicalCaseTimelineRemoteMapping {
    private static let prescribedDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func prescriptionDraft(
        from batch: SparkMedicalSyncAPI.RemotePrescriptionBatchComplete,
        medicalCaseID: Int
    ) -> PrescriptionRecognitionDraft {
        let prescribedAt = batch.prescribedAt.map { prescribedDateFormatter.string(from: $0) }
        let auditedAt = batch.auditedAt.map { prescribedDateFormatter.string(from: $0) }
        let medications = (batch.medications ?? []).map { medicationDraft(from: $0) }
        return PrescriptionRecognitionDraft(
            medicalCase: medicalCaseID,
            prescriberName: batch.prescriberName?.nilIfBlank,
            institutionName: batch.institutionName?.nilIfBlank,
            prescribedAt: prescribedAt,
            diagnosis: (batch.diagnosis ?? "").nilIfBlank,
            batchNo: batch.batchNo?.nilIfBlank,
            status: batch.status?.nilIfBlank ?? "active",
            auditorName: batch.auditorName?.nilIfBlank,
            auditedAt: auditedAt,
            extra: batch.extra,
            medications: medications
        )
    }

    static func medicationDraft(from medication: SparkMedicalSyncAPI.RemoteMedication) -> MedicationRecognitionDraft {
        MedicationRecognitionDraft(
            genericName: medication.genericName.nilIfBlank,
            brandName: medication.brandName.nilIfBlank,
            drugName: medication.drugName.nilIfBlank,
            dosageForm: medication.dosageForm.nilIfBlank,
            strength: medication.strength.nilIfBlank,
            route: medication.route.nilIfBlank,
            dosePerTime: medication.dosePerTime.nilIfBlank,
            doseValue: medication.doseValue.map { Self.formatDoseValue($0) },
            doseUnit: medication.doseUnit.nilIfBlank,
            frequencyCode: medication.frequencyCode.nilIfBlank,
            period: medication.period.nilIfBlank,
            timesPerPeriod: medication.timesPerPeriod.map { String($0) },
            frequencyText: medication.frequencyText.nilIfBlank,
            durationDays: medication.durationDays.map { String($0) },
            instructions: medication.instructions.nilIfBlank,
            reminderEnabled: medication.reminderEnabled,
            reminderTimes: medication.reminderTimes,
            sortOrder: String(medication.sortOrder),
            extra: medication.extra
        )
    }

    private static func formatDoseValue(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(value)
    }

    static func examinationDraft(from report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> MedicalReportRecognitionDraft {
        let details = (report.medExamDetails ?? []).enumerated().map { index, detail in
            MedicalReportItem(
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
                sortOrder: String(detail.sortOrder ?? index)
            )
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
