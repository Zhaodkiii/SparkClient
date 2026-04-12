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
}
