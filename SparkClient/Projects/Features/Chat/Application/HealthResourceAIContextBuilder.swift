import Foundation

/// 已解析健康资料 → AI 上下文正文（经 `HealthResourceRepository` 取数，不拼 UI 卡片摘要）。
struct HealthResourceAIContextBuilder {
    let repository: HealthResourceRepository
    let summaryMapper: HealthResourceSummaryMapper

    func section(
        for ref: HealthResourceRef,
        index: Int,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    ) async -> String? {
        guard let body = await body(for: ref, cachedCompleteData: cachedCompleteData) else {
            return nil
        }
        let title = (
            await summaryMapper.cardSummary(
                for: ref,
                refIndex: index,
                totalRefs: 1,
                cachedCompleteData: cachedCompleteData,
                repository: repository
            )
        ).title
        return "[\(index)] \(title)\n\(body)"
    }

    func body(
        for ref: HealthResourceRef,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil
    ) async -> String? {
        guard let type = ref.typedResource else { return nil }
        let localCache = cachedCompleteData?.memberId == ref.memberID ? cachedCompleteData : nil
        let fmt = HealthResourceRecordFormatting.self

        if let localCache,
           let cachedBody = bodyFromCompleteData(ref: ref, type: type, data: localCache, loadDetails: true),
           fmt.isAIContextBodySufficient(cachedBody, type: type) {
            return cachedBody
        }

        if let networkBody = await bodyFromNetwork(ref: ref, type: type, loadDetails: true),
           fmt.isAIContextBodySufficient(networkBody, type: type) {
            return networkBody
        }

        if let localCache,
           let cachedBody = bodyFromCompleteData(ref: ref, type: type, data: localCache, loadDetails: true) {
            return cachedBody
        }
        return await bodyFromNetwork(ref: ref, type: type, loadDetails: true)
    }

    // MARK: - Complete-data slice

    private func bodyFromCompleteData(
        ref: HealthResourceRef,
        type: HealthResourceType,
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        loadDetails: Bool
    ) -> String? {
        let fmt = HealthResourceRecordFormatting.self
        switch type {
        case .examinationReport:
            guard let report = data.examinationReports?.first(where: { $0.id == ref.resourceID }) else { return nil }
            let details = loadDetails ? report.medExamDetails : nil
            guard fmt.examinationClinicalContentIsPresent(
                findings: report.findings,
                impression: report.impression,
                details: details
            ) else { return nil }
            return fmt.examinationBody(
                itemName: report.itemName,
                reportedAt: report.reportedAt,
                performedAt: report.performedAt,
                organizationName: report.organizationName,
                category: report.category,
                departmentName: report.departmentName,
                doctorName: report.doctorName,
                findings: report.findings,
                impression: report.impression,
                cachedDetails: details
            )
        case .healthExamReport:
            guard let report = data.healthExamReports?.first(where: { $0.id == ref.resourceID }) else { return nil }
            let details = loadDetails ? report.medExamDetails : nil
            guard fmt.healthExamClinicalContentIsPresent(summary: report.summary, details: details) else { return nil }
            return fmt.healthExamBody(
                institutionName: report.institutionName,
                examDate: report.examDate,
                reportNo: report.reportNo,
                summary: report.summary,
                cachedDetails: details
            )
        case .medicalCase:
            guard let item = data.medicalCases?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return fmt.joinLines(date: item.updatedAt, institution: item.hospitalName, summary: item.diagnosisSummary)
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

    // MARK: - Network

    private func bodyFromNetwork(
        ref: HealthResourceRef,
        type: HealthResourceType,
        loadDetails: Bool
    ) async -> String? {
        let fmt = HealthResourceRecordFormatting.self
        switch type {
        case .examinationReport:
            guard case .success(let report) = await repository.retrieveExaminationReport(id: ref.resourceID) else { return nil }
            let details: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
            if loadDetails, case .success(let loaded) = await repository.loadMedExamDetails(
                memberID: ref.memberID,
                businessID: ref.resourceID,
                businessType: type.rawValue
            ) {
                details = loaded
            } else {
                details = nil
            }
            return fmt.examinationBody(
                itemName: report.itemName, reportedAt: report.reportedAt, performedAt: report.performedAt,
                organizationName: report.organizationName, category: report.category,
                departmentName: report.departmentName, doctorName: report.doctorName,
                findings: report.findings, impression: report.impression,
                cachedDetails: details
            )
        case .healthExamReport:
            guard case .success(let report) = await repository.retrieveHealthExamReport(id: ref.resourceID) else { return nil }
            let details: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
            if loadDetails, case .success(let loaded) = await repository.loadMedExamDetails(
                memberID: ref.memberID,
                businessID: ref.resourceID,
                businessType: type.rawValue
            ) {
                details = loaded
            } else {
                details = nil
            }
            return fmt.healthExamBody(
                institutionName: report.institutionName, examDate: report.examDate, reportNo: report.reportNo,
                summary: report.summary, cachedDetails: details
            )
        case .medicalCase:
            guard case .success(let item) = await repository.retrieveMedicalCase(id: ref.resourceID) else { return nil }
            return fmt.joinLines(date: item.updatedAt, institution: item.hospitalName, summary: item.diagnosisSummary)
        case .prescription:
            guard case .success(let item) = await repository.retrievePrescription(id: ref.resourceID) else { return nil }
            return "诊断：\(item.diagnosis)\n机构：\(item.institutionName)\n开方：\(item.prescriberName)"
        case .medicationPlan:
            guard case .success(let item) = await repository.retrieveMedicationPlan(id: ref.resourceID) else { return nil }
            return "\(item.drugName) \(item.dosePerTime) \(item.frequencyText)\n说明：\(item.instructions)"
        case .medicineBox:
            guard case .success(let item) = await repository.retrieveMedicineBox(id: ref.resourceID) else { return nil }
            return "\(item.medicineName) \(item.strength) \(item.dosageForm)\n备注：\(item.notes)"
        case .medicationRecord:
            guard case .success(let item) = await repository.retrieveMedicationRecord(id: ref.resourceID) else { return nil }
            return "计划剂量：\(item.plannedDose) 实际：\(item.actualDose) 状态：\(item.status)"
        case .symptom:
            guard case .success(let item) = await repository.retrieveSymptom(id: ref.resourceID) else { return nil }
            return "\(item.name) 严重度 \(item.severity) 部位 \(item.bodyPart)\n\(item.notes)"
        case .visit:
            guard case .success(let item) = await repository.retrieveVisit(id: ref.resourceID) else { return nil }
            return "\(item.department) \(item.doctorName) \(item.visitType)\n\(item.notes)"
        case .surgery:
            guard case .success(let item) = await repository.retrieveSurgery(id: ref.resourceID) else { return nil }
            return "\(item.procedureName) 术者 \(item.surgeon)\n\(item.notes)"
        case .followUp:
            guard case .success(let item) = await repository.retrieveFollowUp(id: ref.resourceID) else { return nil }
            return "结果：\(item.outcome) 下一步：\(item.nextAction)"
        case .medicationSummary:
            return nil
        }
    }
}
