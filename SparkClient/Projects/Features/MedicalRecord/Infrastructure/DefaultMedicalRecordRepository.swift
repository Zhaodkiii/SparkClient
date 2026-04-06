import Foundation

final class DefaultMedicalRecordRepository: MedicalRecordRepository, @unchecked Sendable {
    private let medicalDataRepository: any MedicalDataRepository

    init(medicalDataRepository: any MedicalDataRepository) {
        self.medicalDataRepository = medicalDataRepository
    }

    func loadRecords(patientID: Int, limit: Int) async -> [MedicalRecord] {
        let snapshot = await medicalDataRepository.loadSnapshot()
        let cases = snapshot.medicalCases
            .filter { $0.memberID == patientID }
            .map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.memberID,
                    title: $0.title,
                    summary: makeCaseSummary($0),
                    occurredAt: $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }
        let visits = snapshot.visits
            .filter { $0.memberID == patientID }
            .map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.memberID,
                    title: $0.department.isEmpty ? "Visit" : $0.department,
                    summary: makeVisitSummary($0),
                    occurredAt: $0.visitedAt ?? $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }
        let surgeries = snapshot.surgeries
            .filter { $0.memberID == patientID }
            .map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.memberID,
                    title: $0.procedureName,
                    summary: makeSurgerySummary($0),
                    occurredAt: $0.performedAt ?? $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }
        let followUps = snapshot.followUps
            .filter { $0.memberID == patientID }
            .map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.memberID,
                    title: $0.method.isEmpty ? "FollowUp" : $0.method,
                    summary: makeFollowUpSummary($0),
                    occurredAt: $0.completedAt ?? $0.plannedAt ?? $0.updatedAt,
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
                    title: $0.itemName,
                    summary: makeExaminationSummary($0),
                    occurredAt: $0.reportedAt ?? $0.performedAt ?? $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }

        let medications = snapshot.medications
            .filter { $0.memberID == patientID }
            .map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.memberID,
                    title: $0.drugName.isEmpty ? "Medication" : $0.drugName,
                    summary: makeMedicationSummary($0),
                    occurredAt: $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }

        return (cases + visits + surgeries + followUps + reports + exams + medications)
            .sorted { lhs, rhs in lhs.occurredAt > rhs.occurredAt }
            .prefix(max(1, limit))
            .map { $0 }
    }

    func buildPatientContextSummary(patientID: Int, limit: Int) async -> String {
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
        let diagnosis = medicalCase.diagnosisSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let hospital = medicalCase.hospitalName.trimmingCharacters(in: .whitespacesAndNewlines)
        if diagnosis.isEmpty == false {
            return isChinese ? "诊断：\(diagnosis)" : "Diagnosis: \(diagnosis)"
        }
        if hospital.isEmpty == false {
            return isChinese ? "机构：\(hospital)" : "Hospital: \(hospital)"
        }
        return isChinese ? "病例记录" : "Medical case record"
    }

    private func makeVisitSummary(_ visit: Visit) -> String {
        let isChinese = PromptLocalizer().language == .zh
        if visit.doctorName.isEmpty == false {
            return isChinese ? "医生：\(visit.doctorName)" : "Doctor: \(visit.doctorName)"
        }
        return isChinese ? "就诊记录" : "Visit record"
    }

    private func makeSurgerySummary(_ surgery: Surgery) -> String {
        let isChinese = PromptLocalizer().language == .zh
        if surgery.surgeon.isEmpty == false {
            return isChinese ? "术者：\(surgery.surgeon)" : "Surgeon: \(surgery.surgeon)"
        }
        return isChinese ? "手术记录" : "Surgery record"
    }

    private func makeFollowUpSummary(_ followUp: FollowUp) -> String {
        let isChinese = PromptLocalizer().language == .zh
        let outcome = followUp.outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        if outcome.isEmpty == false {
            return String(outcome.prefix(120))
        }
        return isChinese ? "随访记录" : "Follow-up record"
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
        let impression = (report.impression ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if impression.isEmpty == false {
            return String(impression.prefix(120))
        }
        let findings = (report.findings ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if findings.isEmpty == false {
            return isChinese ? "所见：\(String(findings.prefix(120)))" : "Findings: \(String(findings.prefix(120)))"
        }
        return isChinese ? "检查报告" : "Examination report"
    }

    private func makeMedicationSummary(_ medication: Medication) -> String {
        let isChinese = PromptLocalizer().language == .zh
        let dosage = medication.dosePerTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let frequency = medication.frequencyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if dosage.isEmpty == false || frequency.isEmpty == false {
            if isChinese {
                return "剂量：\(dosage.isEmpty ? "-" : dosage)，频次：\(frequency.isEmpty ? "-" : frequency)"
            }
            return "Dosage: \(dosage.isEmpty ? "-" : dosage), Frequency: \(frequency.isEmpty ? "-" : frequency)"
        }
        return isChinese ? "用药记录" : "Medication record"
    }
}
