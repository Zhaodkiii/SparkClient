import Foundation

/// 医疗记录仓储默认实现（按需查询版）。
///
/// 说明：
/// - 通过 `SparkMedicalQueryAPI` 分资源拉取数据；
/// - 将不同业务资源统一映射为 `MedicalRecord` 时间线；
/// - 不依赖全量快照主链路。
final class DefaultMedicalRecordRepository: MedicalRecordRepository, @unchecked Sendable {
    private let medicalQueryAPI: SparkMedicalQueryAPI

    init(medicalQueryAPI: SparkMedicalQueryAPI) {
        self.medicalQueryAPI = medicalQueryAPI
    }

    /// 加载指定成员的医疗记录列表，并按时间倒序返回。
    ///
    /// - Parameters:
    ///   - patientID: 当前成员 ID。
    ///   - limit: 最多返回条数，最小为 1。
    /// - Returns: 合并后的统一医疗记录时间线。
    func loadRecords(patientID: Int, limit: Int) async -> [MedicalRecord] {
        // 病例
        let caseRows: [SparkMedicalSyncAPI.RemoteMedicalCase] = (try? await medicalQueryAPI.listMedicalCases(memberID: patientID)) ?? []
        let cases = caseRows.map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.member,
                    title: $0.title,
                    summary: makeCaseSummary($0.diagnosisSummary, hospital: $0.hospitalName),
                    occurredAt: $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }
        // 就诊
        let visitRows: [SparkMedicalSyncAPI.RemoteVisit] = (try? await medicalQueryAPI.listVisits(memberID: patientID)) ?? []
        let visits = visitRows.map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.member,
                    title: $0.department.isEmpty ? "Visit" : $0.department,
                    summary: makeVisitSummary($0.doctorName),
                    occurredAt: $0.visitedAt ?? $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }
        // 手术
        let surgeryRows: [SparkMedicalSyncAPI.RemoteSurgery] = (try? await medicalQueryAPI.listSurgeries(memberID: patientID)) ?? []
        let surgeries = surgeryRows.map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.member,
                    title: $0.procedureName,
                    summary: makeSurgerySummary($0.surgeon),
                    occurredAt: $0.performedAt ?? $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }
        // 随访
        let followUpRows: [SparkMedicalSyncAPI.RemoteFollowUp] = (try? await medicalQueryAPI.listFollowUps(memberID: patientID)) ?? []
        let followUps = followUpRows.map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.member,
                    title: $0.method.isEmpty ? "FollowUp" : $0.method,
                    summary: makeFollowUpSummary($0.outcome),
                    occurredAt: $0.completedAt ?? $0.plannedAt ?? $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }

        // 检查报告
        let examRows: [SparkMedicalSyncAPI.RemoteExaminationReport] = (try? await medicalQueryAPI.listExaminationReports(memberID: patientID)) ?? []
        let exams = examRows.map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.member,
                    title: $0.itemName,
                    summary: makeExaminationSummary(impression: $0.impression, findings: $0.findings),
                    occurredAt: $0.reportedAt ?? $0.performedAt ?? $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }

        // 用药
        let medicationRows: [SparkMedicalSyncAPI.RemoteMedication] = (try? await medicalQueryAPI.listMedications(memberID: patientID)) ?? []
        let medications = medicationRows.map {
                MedicalRecord(
                    id: $0.id,
                    patientID: $0.member,
                    title: $0.drugName.isEmpty ? "Medication" : $0.drugName,
                    summary: makeMedicationSummary(dosage: $0.dosePerTime, frequency: $0.frequencyText),
                    occurredAt: $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }

        // 合并后统一排序并裁剪数量。
        return (cases + visits + surgeries + followUps + exams + medications)
            .sorted { lhs, rhs in lhs.occurredAt > rhs.occurredAt }
            .prefix(max(1, limit))
            .map { $0 }
    }

    /// 生成患者上下文摘要，供 AI prompt 注入最近病历语境。
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

    /// 病例摘要优先级：诊断 > 机构 > 默认文案。
    private func makeCaseSummary(_ diagnosis: String, hospital: String) -> String {
        let isChinese = PromptLocalizer().language == .zh
        let diagnosis = diagnosis.trimmingCharacters(in: .whitespacesAndNewlines)
        let hospital = hospital.trimmingCharacters(in: .whitespacesAndNewlines)
        if diagnosis.isEmpty == false {
            return isChinese ? "诊断：\(diagnosis)" : "Diagnosis: \(diagnosis)"
        }
        if hospital.isEmpty == false {
            return isChinese ? "机构：\(hospital)" : "Hospital: \(hospital)"
        }
        return isChinese ? "病例记录" : "Medical case record"
    }

    /// 就诊摘要优先使用医生信息。
    private func makeVisitSummary(_ doctorName: String) -> String {
        let isChinese = PromptLocalizer().language == .zh
        if doctorName.isEmpty == false {
            return isChinese ? "医生：\(doctorName)" : "Doctor: \(doctorName)"
        }
        return isChinese ? "就诊记录" : "Visit record"
    }

    /// 手术摘要优先使用术者信息。
    private func makeSurgerySummary(_ surgeon: String) -> String {
        let isChinese = PromptLocalizer().language == .zh
        if surgeon.isEmpty == false {
            return isChinese ? "术者：\(surgeon)" : "Surgeon: \(surgeon)"
        }
        return isChinese ? "手术记录" : "Surgery record"
    }

    /// 随访摘要优先使用结局文本，最长 120 字符。
    private func makeFollowUpSummary(_ outcomeInput: String) -> String {
        let isChinese = PromptLocalizer().language == .zh
        let outcome = outcomeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if outcome.isEmpty == false {
            return String(outcome.prefix(120))
        }
        return isChinese ? "随访记录" : "Follow-up record"
    }

    /// 检查报告摘要优先级：结论 > 所见 > 默认文案。
    private func makeExaminationSummary(impression: String?, findings: String?) -> String {
        let isChinese = PromptLocalizer().language == .zh
        let impression = (impression ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if impression.isEmpty == false {
            return String(impression.prefix(120))
        }
        let findings = (findings ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if findings.isEmpty == false {
            return isChinese ? "所见：\(String(findings.prefix(120)))" : "Findings: \(String(findings.prefix(120)))"
        }
        return isChinese ? "检查报告" : "Examination report"
    }

    /// 用药摘要优先展示剂量与频次。
    private func makeMedicationSummary(dosage: String, frequency: String) -> String {
        let isChinese = PromptLocalizer().language == .zh
        let dosage = dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        let frequency = frequency.trimmingCharacters(in: .whitespacesAndNewlines)
        if dosage.isEmpty == false || frequency.isEmpty == false {
            if isChinese {
                return "剂量：\(dosage.isEmpty ? "-" : dosage)，频次：\(frequency.isEmpty ? "-" : frequency)"
            }
            return "Dosage: \(dosage.isEmpty ? "-" : dosage), Frequency: \(frequency.isEmpty ? "-" : frequency)"
        }
        return isChinese ? "用药记录" : "Medication record"
    }
}
