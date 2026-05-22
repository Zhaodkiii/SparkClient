import Foundation

/// 按 `resourceType + resourceID` 单条拉取健康资料（不拉 complete-data 全量）。
struct HealthResourceRecordService {
    let medicalQueryAPI: SparkMedicalQueryAPI

    func aiContextSection(
        ref: HealthResourceRef,
        index: Int,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil
    ) async -> String? {
        guard let body = await aiContextBody(for: ref, cachedCompleteData: cachedCompleteData) else {
            return nil
        }
        let title = (await cardSummary(for: ref, refIndex: index, totalRefs: 1, cachedCompleteData: cachedCompleteData)).title
        return "[\(index)] \(title)\n\(body)"
    }

    func aiContextBody(
        for ref: HealthResourceRef,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil
    ) async -> String? {
        guard let type = ref.typedResource else { return nil }
        let localCache = cachedCompleteData?.memberId == ref.memberID ? cachedCompleteData : nil

        if let localCache,
           let cachedBody = bodyFromCompleteData(ref: ref, type: type, data: localCache, loadDetails: true),
           isAIContextBodySufficient(cachedBody, type: type) {
            return cachedBody
        }

        if let networkBody = await bodyFromNetwork(ref: ref, type: type, loadDetails: true),
           isAIContextBodySufficient(networkBody, type: type) {
            return networkBody
        }

        // 网络失败或仍偏薄时，退回 complete-data 摘要，避免完全无上下文
        if let localCache,
           let cachedBody = bodyFromCompleteData(ref: ref, type: type, data: localCache, loadDetails: true) {
            return cachedBody
        }
        return await bodyFromNetwork(ref: ref, type: type, loadDetails: true)
    }

    func cardSummary(
        for ref: HealthResourceRef,
        refIndex: Int,
        totalRefs: Int,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil
    ) async -> HealthResourceCardSummary {
        let typeLabel = ref.typeBadge ?? ref.typedResource.map { L10n.text($0.localizationKey) } ?? ref.resourceType
        let indexText = totalRefs > 1 ? "\(refIndex)/\(totalRefs)" : "\(refIndex)"

        if let data = cachedCompleteData, data.memberId == ref.memberID,
           let summary = cardSummaryFromCompleteData(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel, data: data) {
            return summary
        }

        guard let type = ref.typedResource else {
            return notFoundSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel)
        }

        if let summary = await cardSummaryFromNetwork(ref: ref, type: type, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel) {
            return summary
        }
        return notFoundSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel)
    }

    // MARK: - Complete-data slice (no network)

    private func bodyFromCompleteData(
        ref: HealthResourceRef,
        type: HealthResourceType,
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        loadDetails: Bool
    ) -> String? {
        switch type {
        case .examinationReport:
            guard let report = data.examinationReports?.first(where: { $0.id == ref.resourceID }) else { return nil }
            let details = loadDetails ? report.medExamDetails : nil
            guard examinationClinicalContentIsPresent(
                findings: report.findings,
                impression: report.impression,
                details: details
            ) else { return nil }
            return examinationBody(
                itemName: report.itemName,
                reportedAt: report.reportedAt,
                performedAt: report.performedAt,
                organizationName: report.organizationName,
                category: report.category,
                departmentName: report.departmentName,
                doctorName: report.doctorName,
                findings: report.findings,
                impression: report.impression,
                memberID: ref.memberID,
                businessID: ref.resourceID,
                businessType: type.rawValue,
                cachedDetails: details
            )
        case .healthExamReport:
            guard let report = data.healthExamReports?.first(where: { $0.id == ref.resourceID }) else { return nil }
            let details = loadDetails ? report.medExamDetails : nil
            guard healthExamClinicalContentIsPresent(summary: report.summary, details: details) else { return nil }
            return healthExamBody(
                institutionName: report.institutionName,
                examDate: report.examDate,
                reportNo: report.reportNo,
                summary: report.summary,
                memberID: ref.memberID,
                businessID: ref.resourceID,
                businessType: type.rawValue,
                cachedDetails: details
            )
        case .medicalCase:
            guard let item = data.medicalCases?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return joinLines(date: item.updatedAt, institution: item.hospitalName, summary: item.diagnosisSummary)
        case .prescription:
            guard let item = data.prescriptions?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return "诊断：\(item.diagnosis)\n机构：\(item.institutionName)\n开方：\(item.prescriberName)"
        case .medicationPlan:
            guard let item = data.medicationPlans?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return "\(item.drugName) \(item.dosePerTime) \(item.frequencyText)\n说明：\(item.instructions)"
        case .medicineBox:
            guard let item = data.medicineBoxes?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return "\(item.medicineName) \(item.strength) \(item.dosageForm)\n备注：\(item.notes)"
        case .medicationRecord:
            guard let item = data.todayMedicationRecords?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return "计划剂量：\(item.plannedDose) 实际：\(item.actualDose) 状态：\(item.status)"
        case .medicationSummary:
            guard let s = data.medicationSummary else { return nil }
            return "今日 \(s.todayTaken)/\(s.todayTotal) 依从率 \(Int(s.adherenceRate * 100))% 活跃计划 \(s.activePlanCount)"
        case .symptom:
            guard let item = data.symptoms?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return "\(item.name) 严重度 \(item.severity) 部位 \(item.bodyPart)\n\(item.notes)"
        case .visit:
            guard let item = data.visits?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return "\(item.department) \(item.doctorName) \(item.visitType)\n\(item.notes)"
        case .surgery:
            guard let item = data.surgeries?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return "\(item.procedureName) 术者 \(item.surgeon)\n\(item.notes)"
        case .followUp:
            guard let item = data.followUps?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return "结果：\(item.outcome) 下一步：\(item.nextAction)"
        }
    }

    private func cardSummaryFromCompleteData(
        ref: HealthResourceRef,
        refIndex: Int,
        indexText: String,
        typeLabel: String,
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) -> HealthResourceCardSummary? {
        guard let type = ref.typedResource else { return nil }
        switch type {
        case .examinationReport:
            guard let report = data.examinationReports?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return examinationCardSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                itemName: report.itemName, reportedAt: report.reportedAt, performedAt: report.performedAt,
                organizationName: report.organizationName, category: report.category,
                findings: report.findings, impression: report.impression,
                attachmentCount: report.attachments?.count)
        case .healthExamReport:
            guard let report = data.healthExamReports?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return healthExamCardSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                institutionName: report.institutionName, examDate: report.examDate, reportNo: report.reportNo,
                summary: report.summary, attachmentCount: report.attachments?.count)
        case .medicalCase:
            guard let item = data.medicalCases?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return HealthResourceCardSummary(
                resourceType: ref.resourceType, resourceId: ref.resourceID, memberId: ref.memberID, refIndex: refIndex,
                status: .loaded, typeLabel: typeLabel,
                title: trimmed(item.title) ?? L10n.text(type.localizationKey),
                dateText: formatDate(item.updatedAt ?? item.createdAt),
                organizationText: trimmed(item.hospitalName),
                summaryText: trimmed(item.diagnosisSummary),
                badgeTexts: [], attachmentCount: item.attachments?.count, indexText: indexText
            )
        default:
            return nil
        }
    }

    // MARK: - Single-resource network

    private func bodyFromNetwork(
        ref: HealthResourceRef,
        type: HealthResourceType,
        loadDetails: Bool
    ) async -> String? {
        switch type {
        case .examinationReport:
            guard let report = try? await medicalQueryAPI.retrieveExaminationReport(id: ref.resourceID) else { return nil }
            return examinationBody(
                itemName: report.itemName, reportedAt: report.reportedAt, performedAt: report.performedAt,
                organizationName: report.organizationName, category: report.category,
                departmentName: report.departmentName, doctorName: report.doctorName,
                findings: report.findings, impression: report.impression,
                memberID: ref.memberID, businessID: ref.resourceID, businessType: type.rawValue,
                cachedDetails: loadDetails ? await loadMedExamDetails(memberID: ref.memberID, businessType: type.rawValue, businessID: ref.resourceID) : nil
            )
        case .healthExamReport:
            guard let report = try? await medicalQueryAPI.retrieveHealthExamReport(id: ref.resourceID) else { return nil }
            return healthExamBody(
                institutionName: report.institutionName, examDate: report.examDate, reportNo: report.reportNo,
                summary: report.summary, memberID: ref.memberID, businessID: ref.resourceID, businessType: type.rawValue,
                cachedDetails: loadDetails ? await loadMedExamDetails(memberID: ref.memberID, businessType: type.rawValue, businessID: ref.resourceID) : nil
            )
        case .medicalCase:
            guard let item = try? await medicalQueryAPI.retrieveMedicalCase(id: ref.resourceID) else { return nil }
            return joinLines(date: item.updatedAt, institution: item.hospitalName, summary: item.diagnosisSummary)
        case .prescription:
            guard let item = try? await medicalQueryAPI.retrievePrescription(id: ref.resourceID) else { return nil }
            return "诊断：\(item.diagnosis)\n机构：\(item.institutionName)\n开方：\(item.prescriberName)"
        case .medicationPlan:
            guard let item = try? await medicalQueryAPI.retrieveMedicationPlan(id: ref.resourceID) else { return nil }
            return "\(item.drugName) \(item.dosePerTime) \(item.frequencyText)\n说明：\(item.instructions)"
        case .medicineBox:
            guard let item = try? await medicalQueryAPI.retrieveMedicineBox(id: ref.resourceID) else { return nil }
            return "\(item.medicineName) \(item.strength) \(item.dosageForm)\n备注：\(item.notes)"
        case .medicationRecord:
            guard let item = try? await medicalQueryAPI.retrieveMedicationRecord(id: ref.resourceID) else { return nil }
            return "计划剂量：\(item.plannedDose) 实际：\(item.actualDose) 状态：\(item.status)"
        case .symptom:
            guard let item = try? await medicalQueryAPI.retrieveSymptom(id: ref.resourceID) else { return nil }
            return "\(item.name) 严重度 \(item.severity) 部位 \(item.bodyPart)\n\(item.notes)"
        case .visit:
            guard let item = try? await medicalQueryAPI.retrieveVisit(id: ref.resourceID) else { return nil }
            return "\(item.department) \(item.doctorName) \(item.visitType)\n\(item.notes)"
        case .surgery:
            guard let item = try? await medicalQueryAPI.retrieveSurgery(id: ref.resourceID) else { return nil }
            return "\(item.procedureName) 术者 \(item.surgeon)\n\(item.notes)"
        case .followUp:
            guard let item = try? await medicalQueryAPI.retrieveFollowUp(id: ref.resourceID) else { return nil }
            return "结果：\(item.outcome) 下一步：\(item.nextAction)"
        case .medicationSummary:
            return nil
        }
    }

    private func cardSummaryFromNetwork(
        ref: HealthResourceRef,
        type: HealthResourceType,
        refIndex: Int,
        indexText: String,
        typeLabel: String
    ) async -> HealthResourceCardSummary? {
        switch type {
        case .examinationReport:
            guard let report = try? await medicalQueryAPI.retrieveExaminationReport(id: ref.resourceID) else { return nil }
            return examinationCardSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                itemName: report.itemName, reportedAt: report.reportedAt, performedAt: report.performedAt,
                organizationName: report.organizationName, category: report.category,
                findings: report.findings, impression: report.impression, attachmentCount: nil)
        case .healthExamReport:
            guard let report = try? await medicalQueryAPI.retrieveHealthExamReport(id: ref.resourceID) else { return nil }
            return healthExamCardSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                institutionName: report.institutionName, examDate: report.examDate, reportNo: report.reportNo,
                summary: report.summary, attachmentCount: nil)
        case .medicalCase:
            guard let item = try? await medicalQueryAPI.retrieveMedicalCase(id: ref.resourceID) else { return nil }
            return HealthResourceCardSummary(
                resourceType: ref.resourceType, resourceId: ref.resourceID, memberId: ref.memberID, refIndex: refIndex,
                status: .loaded, typeLabel: typeLabel,
                title: trimmed(item.title) ?? L10n.text(type.localizationKey),
                dateText: formatDate(item.updatedAt),
                organizationText: trimmed(item.hospitalName),
                summaryText: trimmed(item.diagnosisSummary),
                badgeTexts: [], attachmentCount: nil, indexText: indexText
            )
        case .prescription:
            guard let item = try? await medicalQueryAPI.retrievePrescription(id: ref.resourceID) else { return nil }
            return loadedSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                title: trimmed(item.diagnosis) ?? L10n.text(type.localizationKey),
                dateText: formatDate(item.prescribedAt ?? item.updatedAt),
                organizationText: trimmed(item.institutionName),
                summaryText: trimmed(item.diagnosis))
        case .medicationPlan:
            guard let item = try? await medicalQueryAPI.retrieveMedicationPlan(id: ref.resourceID) else { return nil }
            return loadedSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                title: trimmed(item.drugName) ?? L10n.text(type.localizationKey),
                dateText: formatDate(item.startDate),
                organizationText: trimmed(item.frequencyText),
                summaryText: trimmed(item.instructions))
        case .medicineBox:
            guard let item = try? await medicalQueryAPI.retrieveMedicineBox(id: ref.resourceID) else { return nil }
            return loadedSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                title: trimmed(item.medicineName) ?? L10n.text(type.localizationKey),
                dateText: formatDate(item.expireDate ?? item.updatedAt),
                organizationText: trimmed(item.brandName),
                summaryText: trimmed(item.notes))
        default:
            return nil
        }
    }

    private func loadMedExamDetails(memberID: Int, businessType: String, businessID: Int) async -> [SparkMedicalSyncAPI.RemoteMedExamDetail]? {
        try? await medicalQueryAPI.listMedExamDetails(memberID: memberID, businessType: businessType, businessID: businessID)
    }

    // MARK: - Context sufficiency

    /// complete-data 首页快照常缺所见/结论/指标；不足时必须走单条 retrieve + listMedExamDetails。
    private func isAIContextBodySufficient(_ body: String, type: HealthResourceType) -> Bool {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBody.isEmpty == false else { return false }
        switch type {
        case .examinationReport, .healthExamReport:
            return trimmedBody.contains("所见：")
                || trimmedBody.contains("结论：")
                || trimmedBody.contains("指标：")
                || trimmedBody.count >= 120
        default:
            return true
        }
    }

    private func examinationClinicalContentIsPresent(
        findings: String?,
        impression: String?,
        details: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
    ) -> Bool {
        trimmed(findings) != nil
            || trimmed(impression) != nil
            || (details?.isEmpty == false)
    }

    private func healthExamClinicalContentIsPresent(
        summary: String?,
        details: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
    ) -> Bool {
        trimmed(summary) != nil || (details?.isEmpty == false)
    }

    // MARK: - Format helpers

    private func examinationBody(
        itemName: String?, reportedAt: Date?, performedAt: Date?, organizationName: String?,
        category: String?, departmentName: String?, doctorName: String?, findings: String?, impression: String?,
        memberID: Int, businessID: Int, businessType: String,
        cachedDetails: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
    ) -> String {
        var lines: [String] = []
        if let name = trimmed(itemName) { lines.append(name) }
        lines.append(contentsOf: joinLines(date: reportedAt ?? performedAt, institution: organizationName, summary: nil)
            .split(separator: "\n")
            .map(String.init))
        if let category = trimmed(category) { lines.append("类别：\(category)") }
        if let department = trimmed(departmentName) { lines.append("科室：\(department)") }
        if let doctor = trimmed(doctorName) { lines.append("医生：\(doctor)") }
        if let findings = trimmed(findings) { lines.append("所见：\(findings)") }
        if let impression = trimmed(impression) { lines.append("结论：\(impression)") }
        appendMedExamLines(&lines, details: cachedDetails)
        return lines.joined(separator: "\n")
    }

    private func healthExamBody(
        institutionName: String?, examDate: Date?, reportNo: String?, summary: String?,
        memberID: Int, businessID: Int, businessType: String,
        cachedDetails: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
    ) -> String {
        var lines = joinLines(date: examDate, institution: institutionName, summary: summary).split(separator: "\n").map(String.init)
        if let reportNo = trimmed(reportNo) { lines.append("报告号：\(reportNo)") }
        appendMedExamLines(&lines, details: cachedDetails)
        return lines.joined(separator: "\n")
    }

    private func examinationCardSummary(
        ref: HealthResourceRef, refIndex: Int, indexText: String, typeLabel: String,
        itemName: String?, reportedAt: Date?, performedAt: Date?, organizationName: String?, category: String?,
        findings: String?, impression: String?, attachmentCount: Int?
    ) -> HealthResourceCardSummary {
        loadedSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
            title: trimmed(itemName) ?? L10n.text("chat.ask_report.resource_type.examination_report"),
            dateText: formatDate(reportedAt ?? performedAt),
            organizationText: trimmed(organizationName),
            summaryText: trimmed(impression) ?? trimmed(findings),
            badgeTexts: trimmed(category).map { [$0] } ?? [],
            attachmentCount: attachmentCount)
    }

    private func healthExamCardSummary(
        ref: HealthResourceRef, refIndex: Int, indexText: String, typeLabel: String,
        institutionName: String?, examDate: Date?, reportNo: String?, summary: String?, attachmentCount: Int?
    ) -> HealthResourceCardSummary {
        loadedSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
            title: trimmed(institutionName) ?? L10n.text("chat.ask_report.resource_type.health_exam_report"),
            dateText: formatDate(examDate),
            organizationText: trimmed(reportNo),
            summaryText: trimmed(summary),
            badgeTexts: [], attachmentCount: attachmentCount)
    }

    private func loadedSummary(
        ref: HealthResourceRef, refIndex: Int, indexText: String, typeLabel: String,
        title: String, dateText: String?, organizationText: String?, summaryText: String?,
        badgeTexts: [String] = [], attachmentCount: Int? = nil
    ) -> HealthResourceCardSummary {
        HealthResourceCardSummary(
            resourceType: ref.resourceType, resourceId: ref.resourceID, memberId: ref.memberID, refIndex: refIndex,
            status: .loaded, typeLabel: typeLabel, title: title, dateText: dateText,
            organizationText: organizationText, summaryText: summaryText,
            badgeTexts: badgeTexts, attachmentCount: attachmentCount, indexText: indexText
        )
    }

    private func notFoundSummary(
        ref: HealthResourceRef, refIndex: Int, indexText: String, typeLabel: String
    ) -> HealthResourceCardSummary {
        HealthResourceCardSummary(
            resourceType: ref.resourceType, resourceId: ref.resourceID, memberId: ref.memberID, refIndex: refIndex,
            status: .notFound, typeLabel: typeLabel, title: ref.displayTitle,
            dateText: nil, organizationText: nil, summaryText: nil,
            badgeTexts: [], attachmentCount: nil, indexText: indexText
        )
    }

    private func appendMedExamLines(_ lines: inout [String], details: [SparkMedicalSyncAPI.RemoteMedExamDetail]?) {
        guard let details, details.isEmpty == false else { return }
        lines.append("指标：")
        for row in details.prefix(40) {
            let reference = row.referenceRange.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = reference.isEmpty ? "" : " 参考 \(reference)"
            lines.append("· \(row.itemName): \(row.resultValue ?? "—") \(row.unit) \(row.flag)\(suffix)")
        }
    }

    private func joinLines(date: Date?, institution: String?, summary: String?) -> String {
        var lines: [String] = []
        if let institution = trimmed(institution) { lines.append("机构：\(institution)") }
        if let date, let text = formatDate(date) { lines.append("日期：\(text)") }
        if let summary = trimmed(summary) { lines.append(summary) }
        return lines.joined(separator: "\n")
    }

    private func formatDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
