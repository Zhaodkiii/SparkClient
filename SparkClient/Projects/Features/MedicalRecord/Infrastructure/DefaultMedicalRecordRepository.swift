import Foundation

final class DefaultMedicalRecordRepository: MedicalRecordRepository, @unchecked Sendable {
    private let medicalDataRepository: any MedicalDataRepository

    init(medicalDataRepository: any MedicalDataRepository) {
        self.medicalDataRepository = medicalDataRepository
    }

    func loadRecords(patientID: UUID, limit: Int) async -> [MedicalRecord] {
        let snapshot = await medicalDataRepository.loadSnapshot()
        let cases = snapshot.medicalCases
            .filter { $0.memberID == patientID }
            .map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.memberID,
                    title: $0.title,
                    summary: makeCaseSummary($0),
                    occurredAt: $0.visitDate,
                    updatedAt: $0.updatedAt
                )
            }

        let reports = snapshot.medicalReports
            .filter { $0.memberID == patientID }
            .map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.memberID,
                    title: $0.title,
                    summary: makeReportSummary($0),
                    occurredAt: $0.date,
                    updatedAt: $0.updatedAt
                )
            }

        let exams = snapshot.examinationReports
            .filter { $0.memberID == patientID }
            .map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.memberID,
                    title: $0.reportName,
                    summary: makeExaminationSummary($0),
                    occurredAt: $0.date,
                    updatedAt: $0.updatedAt
                )
            }

        let prescriptions = snapshot.prescriptions
            .filter { $0.memberID == patientID }
            .map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.memberID,
                    title: $0.drugName,
                    summary: makePrescriptionSummary($0),
                    occurredAt: $0.startDate ?? $0.endDate ?? $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }

        return (cases + reports + exams + prescriptions)
            .sorted { lhs, rhs in lhs.occurredAt > rhs.occurredAt }
            .prefix(max(1, limit))
            .map { $0 }
    }

    func buildPatientContextSummary(patientID: UUID, limit: Int) async -> String {
        let records = await loadRecords(patientID: patientID, limit: limit)
        guard records.isEmpty == false else { return "" }
        let promptLocalizer = PromptLocalizer()

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let lines = records.map { record in
            let dateText = formatter.string(from: record.occurredAt)
            return promptLocalizer.contextLine(
                dateText: dateText,
                title: record.title,
                summary: record.summary
            )
        }

        return """
        \(promptLocalizer.contextSummaryHeader(recordCount: records.count))
        \(lines.joined(separator: "\n"))
        """
    }

    private func makeCaseSummary(_ medicalCase: MedicalCase) -> String {
        let isChinese = PromptLocalizer().language == .zh
        let diagnosis = medicalCase.diagnosis.trimmingCharacters(in: .whitespacesAndNewlines)
        let complaint = medicalCase.chiefComplaint.trimmingCharacters(in: .whitespacesAndNewlines)
        if diagnosis.isEmpty == false {
            return isChinese ? "诊断：\(diagnosis)" : "Diagnosis: \(diagnosis)"
        }
        if complaint.isEmpty == false {
            return isChinese ? "主诉：\(complaint)" : "Chief complaint: \(complaint)"
        }
        return isChinese ? "病例记录" : "Medical case record"
    }

    private func makeReportSummary(_ report: MedicalReport) -> String {
        let isChinese = PromptLocalizer().language == .zh
        let content = report.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty == false {
            return String(content.prefix(120))
        }
        let hospital = report.hospital.trimmingCharacters(in: .whitespacesAndNewlines)
        if hospital.isEmpty == false {
            return isChinese ? "医院：\(hospital)" : "Hospital: \(hospital)"
        }
        return isChinese ? "医疗报告" : "Medical report"
    }

    private func makeExaminationSummary(_ report: ExaminationReport) -> String {
        let isChinese = PromptLocalizer().language == .zh
        let conclusion = report.conclusion.trimmingCharacters(in: .whitespacesAndNewlines)
        if conclusion.isEmpty == false {
            return String(conclusion.prefix(120))
        }
        let advice = report.doctorAdvice.trimmingCharacters(in: .whitespacesAndNewlines)
        if advice.isEmpty == false {
            return isChinese ? "建议：\(String(advice.prefix(120)))" : "Advice: \(String(advice.prefix(120)))"
        }
        return isChinese ? "检查报告" : "Examination report"
    }

    private func makePrescriptionSummary(_ prescription: Prescription) -> String {
        let isChinese = PromptLocalizer().language == .zh
        let dosage = prescription.dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        let frequency = prescription.frequency.trimmingCharacters(in: .whitespacesAndNewlines)
        if dosage.isEmpty == false || frequency.isEmpty == false {
            if isChinese {
                return "剂量：\(dosage.isEmpty ? "-" : dosage)，频次：\(frequency.isEmpty ? "-" : frequency)"
            }
            return "Dosage: \(dosage.isEmpty ? "-" : dosage), Frequency: \(frequency.isEmpty ? "-" : frequency)"
        }
        return isChinese ? "处方记录" : "Prescription record"
    }
}
