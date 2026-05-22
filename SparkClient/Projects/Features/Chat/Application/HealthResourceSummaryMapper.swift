import Foundation

/// 远端健康资料模型 → 消息卡片 / 选择页摘要（不发起网络编排，网络经 `HealthResourceRepository`）。
struct HealthResourceSummaryMapper {
    func cardSummary(
        for ref: HealthResourceRef,
        refIndex: Int,
        totalRefs: Int,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        repository: HealthResourceRepository
    ) async -> HealthResourceCardSummary {
        let typeLabel = ref.typeBadge ?? ref.typedResource.map { L10n.text($0.localizationKey) } ?? ref.resourceType
        let indexText = totalRefs > 1 ? "\(refIndex)/\(totalRefs)" : "\(refIndex)"

        if let data = cachedCompleteData, data.memberId == ref.memberID,
           let summary = cardSummaryFromCompleteData(
               ref: ref,
               refIndex: refIndex,
               indexText: indexText,
               typeLabel: typeLabel,
               data: data
           ) {
            return summary
        }

        guard let type = ref.typedResource else {
            return notFoundSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel)
        }

        if let summary = await cardSummaryFromNetwork(
            ref: ref,
            type: type,
            refIndex: refIndex,
            indexText: indexText,
            typeLabel: typeLabel,
            repository: repository
        ) {
            return summary
        }
        return notFoundSummary(ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel)
    }

    // MARK: - Complete-data

    private func cardSummaryFromCompleteData(
        ref: HealthResourceRef,
        refIndex: Int,
        indexText: String,
        typeLabel: String,
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) -> HealthResourceCardSummary? {
        guard let type = ref.typedResource else { return nil }
        let fmt = HealthResourceRecordFormatting.self
        switch type {
        case .examinationReport:
            guard let report = data.examinationReports?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return examinationCardSummary(
                ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                itemName: report.itemName, reportedAt: report.reportedAt, performedAt: report.performedAt,
                organizationName: report.organizationName, category: report.category,
                findings: report.findings, impression: report.impression,
                attachmentCount: report.attachments?.count
            )
        case .healthExamReport:
            guard let report = data.healthExamReports?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return healthExamCardSummary(
                ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                institutionName: report.institutionName, examDate: report.examDate, reportNo: report.reportNo,
                summary: report.summary, attachmentCount: report.attachments?.count
            )
        case .medicalCase:
            guard let item = data.medicalCases?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return HealthResourceCardSummary(
                resourceType: ref.resourceType, resourceId: ref.resourceID, memberId: ref.memberID, refIndex: refIndex,
                status: .loaded, typeLabel: typeLabel,
                title: fmt.trimmed(item.title) ?? L10n.text(type.localizationKey),
                dateText: fmt.formatDate(item.updatedAt ?? item.createdAt),
                organizationText: fmt.trimmed(item.hospitalName),
                summaryText: fmt.trimmed(item.diagnosisSummary),
                badgeTexts: [], attachmentCount: item.attachments?.count, indexText: indexText
            )
        default:
            return nil
        }
    }

    // MARK: - Network

    private func cardSummaryFromNetwork(
        ref: HealthResourceRef,
        type: HealthResourceType,
        refIndex: Int,
        indexText: String,
        typeLabel: String,
        repository: HealthResourceRepository
    ) async -> HealthResourceCardSummary? {
        let fmt = HealthResourceRecordFormatting.self
        switch type {
        case .examinationReport:
            guard case .success(let report) = await repository.retrieveExaminationReportWithAttachments(id: ref.resourceID) else {
                return nil
            }
            return examinationCardSummary(
                ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                itemName: report.itemName, reportedAt: report.reportedAt, performedAt: report.performedAt,
                organizationName: report.organizationName, category: report.category,
                findings: report.findings, impression: report.impression,
                attachmentCount: report.attachments?.count
            )
        case .healthExamReport:
            guard case .success(let report) = await repository.retrieveHealthExamReportWithAttachments(id: ref.resourceID) else {
                return nil
            }
            return healthExamCardSummary(
                ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                institutionName: report.institutionName, examDate: report.examDate, reportNo: report.reportNo,
                summary: report.summary, attachmentCount: report.attachments?.count
            )
        case .medicalCase:
            guard case .success(let item) = await repository.retrieveMedicalCase(id: ref.resourceID) else { return nil }
            return HealthResourceCardSummary(
                resourceType: ref.resourceType, resourceId: ref.resourceID, memberId: ref.memberID, refIndex: refIndex,
                status: .loaded, typeLabel: typeLabel,
                title: fmt.trimmed(item.title) ?? L10n.text(type.localizationKey),
                dateText: fmt.formatDate(item.updatedAt),
                organizationText: fmt.trimmed(item.hospitalName),
                summaryText: fmt.trimmed(item.diagnosisSummary),
                badgeTexts: [], attachmentCount: nil, indexText: indexText
            )
        case .prescription:
            guard case .success(let item) = await repository.retrievePrescription(id: ref.resourceID) else { return nil }
            return loadedSummary(
                ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                title: fmt.trimmed(item.diagnosis) ?? L10n.text(type.localizationKey),
                dateText: fmt.formatDate(item.prescribedAt ?? item.updatedAt),
                organizationText: fmt.trimmed(item.institutionName),
                summaryText: fmt.trimmed(item.diagnosis)
            )
        case .medicationPlan:
            guard case .success(let item) = await repository.retrieveMedicationPlan(id: ref.resourceID) else { return nil }
            return loadedSummary(
                ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                title: fmt.trimmed(item.drugName) ?? L10n.text(type.localizationKey),
                dateText: fmt.formatDate(item.startDate),
                organizationText: fmt.trimmed(item.frequencyText),
                summaryText: fmt.trimmed(item.instructions)
            )
        case .medicineBox:
            guard case .success(let item) = await repository.retrieveMedicineBox(id: ref.resourceID) else { return nil }
            return loadedSummary(
                ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
                title: fmt.trimmed(item.medicineName) ?? L10n.text(type.localizationKey),
                dateText: fmt.formatDate(item.expireDate ?? item.updatedAt),
                organizationText: fmt.trimmed(item.brandName),
                summaryText: fmt.trimmed(item.notes)
            )
        default:
            return nil
        }
    }

    // MARK: - Card builders

    private func examinationCardSummary(
        ref: HealthResourceRef,
        refIndex: Int,
        indexText: String,
        typeLabel: String,
        itemName: String?,
        reportedAt: Date?,
        performedAt: Date?,
        organizationName: String?,
        category: String?,
        findings: String?,
        impression: String?,
        attachmentCount: Int?
    ) -> HealthResourceCardSummary {
        let fmt = HealthResourceRecordFormatting.self
        return loadedSummary(
            ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
            title: fmt.trimmed(itemName) ?? L10n.text("chat.ask_report.resource_type.examination_report"),
            dateText: fmt.formatDate(reportedAt ?? performedAt),
            organizationText: fmt.trimmed(organizationName),
            summaryText: fmt.trimmed(impression) ?? fmt.trimmed(findings),
            badgeTexts: fmt.trimmed(category).map { [$0] } ?? [],
            attachmentCount: attachmentCount
        )
    }

    private func healthExamCardSummary(
        ref: HealthResourceRef,
        refIndex: Int,
        indexText: String,
        typeLabel: String,
        institutionName: String?,
        examDate: Date?,
        reportNo: String?,
        summary: String?,
        attachmentCount: Int?
    ) -> HealthResourceCardSummary {
        let fmt = HealthResourceRecordFormatting.self
        return loadedSummary(
            ref: ref, refIndex: refIndex, indexText: indexText, typeLabel: typeLabel,
            title: fmt.trimmed(institutionName) ?? L10n.text("chat.ask_report.resource_type.health_exam_report"),
            dateText: fmt.formatDate(examDate),
            organizationText: fmt.trimmed(reportNo),
            summaryText: fmt.trimmed(summary),
            badgeTexts: [], attachmentCount: attachmentCount
        )
    }

    private func loadedSummary(
        ref: HealthResourceRef,
        refIndex: Int,
        indexText: String,
        typeLabel: String,
        title: String,
        dateText: String?,
        organizationText: String?,
        summaryText: String?,
        badgeTexts: [String] = [],
        attachmentCount: Int? = nil
    ) -> HealthResourceCardSummary {
        HealthResourceCardSummary(
            resourceType: ref.resourceType, resourceId: ref.resourceID, memberId: ref.memberID, refIndex: refIndex,
            status: .loaded, typeLabel: typeLabel, title: title, dateText: dateText,
            organizationText: organizationText, summaryText: summaryText,
            badgeTexts: badgeTexts, attachmentCount: attachmentCount, indexText: indexText
        )
    }

    private func notFoundSummary(
        ref: HealthResourceRef,
        refIndex: Int,
        indexText: String,
        typeLabel: String
    ) -> HealthResourceCardSummary {
        HealthResourceCardSummary(
            resourceType: ref.resourceType, resourceId: ref.resourceID, memberId: ref.memberID, refIndex: refIndex,
            status: .notFound, typeLabel: typeLabel, title: ref.displayTitle,
            dateText: nil, organizationText: nil, summaryText: nil,
            badgeTexts: [], attachmentCount: nil, indexText: indexText
        )
    }
}
