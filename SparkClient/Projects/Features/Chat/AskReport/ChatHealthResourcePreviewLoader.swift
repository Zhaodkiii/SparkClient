import Foundation

enum ChatHealthResourcePreviewLoader {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func load(
        ref: HealthResourceRef,
        medicalQueryAPI: SparkMedicalQueryAPI,
        memberName: String?,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        fetchCompleteData: ((Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData)?
    ) async -> ChatHealthResourcePreviewContent? {
        guard let type = ref.typedResource else { return nil }
        let localCache = cachedCompleteData?.memberId == ref.memberID ? cachedCompleteData : nil

        if let content = await loadFromCompleteData(ref: ref, type: type, memberName: memberName, data: localCache),
           content.hasClinicalBody {
            return content
        }

        if let remote = await loadFromNetwork(
            ref: ref,
            type: type,
            memberName: memberName,
            medicalQueryAPI: medicalQueryAPI
        ), remote.hasClinicalBody {
            return remote
        }

        if let refreshedCache = await refreshCompleteData(
            memberID: ref.memberID,
            fetchCompleteData: fetchCompleteData
        ),
           let content = await loadFromCompleteData(ref: ref, type: type, memberName: memberName, data: refreshedCache),
           content.hasClinicalBody {
            return content
        }

        if let thinCache = await loadFromCompleteData(ref: ref, type: type, memberName: memberName, data: localCache) {
            return thinCache
        }
        if let thinNetwork = await loadFromNetwork(ref: ref, type: type, memberName: memberName, medicalQueryAPI: medicalQueryAPI) {
            return thinNetwork
        }
        return fallbackContent(ref: ref, memberName: memberName)
    }

    // MARK: - Complete-data

    private static func loadFromCompleteData(
        ref: HealthResourceRef,
        type: HealthResourceType,
        memberName: String?,
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    ) async -> ChatHealthResourcePreviewContent? {
        guard let data else { return nil }
        switch type {
        case .examinationReport:
            guard let report = data.examinationReports?.first(where: { $0.id == ref.resourceID }) else { return nil }
            var details = report.medExamDetails
            if details == nil || details?.isEmpty == true {
                details = nil
            }
            return examinationContent(
                ref: ref,
                memberName: memberName,
                itemName: report.itemName,
                reportedAt: report.reportedAt,
                performedAt: report.performedAt,
                organizationName: report.organizationName,
                category: report.category,
                subCategory: report.subCategory,
                departmentName: report.departmentName,
                doctorName: report.doctorName,
                findings: report.findings,
                impression: report.impression,
                attachments: report.attachments,
                details: details
            )
        case .healthExamReport:
            guard let report = data.healthExamReports?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return healthExamContent(
                ref: ref,
                memberName: memberName,
                institutionName: report.institutionName,
                examDate: report.examDate,
                reportNo: report.reportNo,
                summary: report.summary,
                attachments: report.attachments,
                details: report.medExamDetails
            )
        case .medicalCase:
            guard let item = data.medicalCases?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return genericContent(
                ref: ref,
                memberName: memberName,
                title: trimmed(item.title) ?? ref.displayTitle,
                date: item.updatedAt ?? item.createdAt,
                organization: item.hospitalName,
                summary: item.diagnosisSummary,
                extraLines: symptomLines(data: data, caseID: item.id),
                attachments: item.attachments
            )
        case .prescription:
            guard let item = data.prescriptions?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return genericContent(
                ref: ref,
                memberName: memberName,
                title: trimmed(item.diagnosis) ?? ref.displayTitle,
                date: item.prescribedAt ?? item.updatedAt,
                organization: item.institutionName,
                summary: trimmed(item.diagnosis),
                extraLines: [
                    line("chat.ask_report.preview.prescriber_format", item.prescriberName),
                    line("chat.ask_report.preview.rx_no_format", item.prescriptionNo)
                ].compactMap { $0 },
                attachments: item.attachments
            )
        case .medicationPlan:
            guard let item = data.medicationPlans?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return genericContent(
                ref: ref,
                memberName: memberName,
                title: trimmed(item.drugName) ?? ref.displayTitle,
                date: item.startDate,
                organization: item.frequencyText,
                summary: trimmed(item.instructions),
                extraLines: [
                    "\(item.dosePerTime) \(item.doseUnit)".trimmingCharacters(in: .whitespaces),
                    planRange(start: item.startDate, end: item.endDate)
                ].filter { $0.isEmpty == false },
                attachments: item.attachments
            )
        case .medicineBox:
            guard let item = data.medicineBoxes?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return genericContent(
                ref: ref,
                memberName: memberName,
                title: trimmed(item.medicineName) ?? ref.displayTitle,
                date: item.expireDate ?? item.updatedAt,
                organization: item.brandName,
                summary: trimmed(item.notes),
                extraLines: [item.strength, item.dosageForm].compactMap { trimmed($0) },
                attachments: item.attachments
            )
        case .symptom:
            guard let item = data.symptoms?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return genericContent(
                ref: ref, memberName: memberName,
                title: item.name, date: item.startedAt ?? item.updatedAt,
                organization: item.severity, summary: trimmed(item.notes),
                extraLines: [item.bodyPart], attachments: nil
            )
        case .visit:
            guard let item = data.visits?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return genericContent(
                ref: ref, memberName: memberName,
                title: trimmed(item.department) ?? ref.displayTitle,
                date: item.visitedAt ?? item.updatedAt,
                organization: item.doctorName,
                summary: trimmed(item.notes),
                extraLines: [item.visitType, item.visitNo], attachments: nil
            )
        case .surgery:
            guard let item = data.surgeries?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return genericContent(
                ref: ref, memberName: memberName,
                title: item.procedureName, date: item.performedAt ?? item.updatedAt,
                organization: item.surgeon, summary: trimmed(item.notes),
                extraLines: [item.site, item.anesthesiaType], attachments: nil
            )
        case .followUp:
            guard let item = data.followUps?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return genericContent(
                ref: ref, memberName: memberName,
                title: L10n.text("chat.ask_report.resource_type.follow_up"),
                date: item.completedAt ?? item.plannedAt ?? item.updatedAt,
                organization: item.method,
                summary: trimmed(item.outcome),
                extraLines: [trimmed(item.nextAction)].compactMap { $0 },
                attachments: nil
            )
        case .medicationRecord:
            guard let item = data.todayMedicationRecords?.first(where: { $0.id == ref.resourceID }) else { return nil }
            let planName = data.medicationPlans?.first(where: { $0.id == item.plan })?.drugName
            return genericContent(
                ref: ref, memberName: memberName,
                title: trimmed(planName) ?? ref.displayTitle,
                date: item.scheduledAt,
                organization: item.status,
                summary: trimmed(item.notes),
                extraLines: ["\(item.plannedDose) → \(item.actualDose)"],
                attachments: nil
            )
        case .medicationSummary:
            guard let summary = data.medicationSummary else { return nil }
            return genericContent(
                ref: ref, memberName: memberName,
                title: L10n.text("chat.ask_report.resource_type.medication_summary"),
                date: Date(),
                organization: nil,
                summary: String(
                    format: L10n.text("chat.ask_report.medication_summary.subtitle_format"),
                    summary.todayTaken,
                    summary.todayTotal
                ),
                extraLines: [
                    String(format: L10n.text("chat.ask_report.preview.adherence_format"), Int(summary.adherenceRate * 100)),
                    String(format: L10n.text("chat.ask_report.preview.active_plans_format"), summary.activePlanCount)
                ],
                attachments: nil
            )
        }
    }

    // MARK: - Network

    private static func loadFromNetwork(
        ref: HealthResourceRef,
        type: HealthResourceType,
        memberName: String?,
        medicalQueryAPI: SparkMedicalQueryAPI
    ) async -> ChatHealthResourcePreviewContent? {
        switch type {
        case .examinationReport:
            guard let report = try? await medicalQueryAPI.retrieveExaminationReport(id: ref.resourceID) else { return nil }
            let details = try? await medicalQueryAPI.listMedExamDetails(
                memberID: ref.memberID,
                businessType: type.rawValue,
                businessID: ref.resourceID
            )
            return examinationContent(
                ref: ref,
                memberName: memberName,
                itemName: report.itemName,
                reportedAt: report.reportedAt,
                performedAt: report.performedAt,
                organizationName: report.organizationName,
                category: report.category,
                subCategory: report.subCategory,
                departmentName: report.departmentName,
                doctorName: report.doctorName,
                findings: report.findings,
                impression: report.impression,
                attachments: nil,
                details: details
            )
        case .healthExamReport:
            guard let report = try? await medicalQueryAPI.retrieveHealthExamReport(id: ref.resourceID) else { return nil }
            let details = try? await medicalQueryAPI.listMedExamDetails(
                memberID: ref.memberID,
                businessType: type.rawValue,
                businessID: ref.resourceID
            )
            return healthExamContent(
                ref: ref,
                memberName: memberName,
                institutionName: report.institutionName,
                examDate: report.examDate,
                reportNo: report.reportNo,
                summary: report.summary,
                attachments: nil,
                details: details
            )
        case .medicalCase:
            guard let item = try? await medicalQueryAPI.retrieveMedicalCase(id: ref.resourceID) else { return nil }
            return genericContent(
                ref: ref, memberName: memberName,
                title: trimmed(item.title) ?? ref.displayTitle,
                date: item.updatedAt,
                organization: item.hospitalName,
                summary: item.diagnosisSummary,
                extraLines: [], attachments: nil
            )
        case .prescription:
            guard let item = try? await medicalQueryAPI.retrievePrescription(id: ref.resourceID) else { return nil }
            return genericContent(
                ref: ref, memberName: memberName,
                title: trimmed(item.diagnosis) ?? ref.displayTitle,
                date: item.prescribedAt ?? item.updatedAt,
                organization: item.institutionName,
                summary: trimmed(item.diagnosis),
                extraLines: [item.prescriberName, item.prescriptionNo ?? ""].filter { $0.isEmpty == false },
                attachments: item.attachments
            )
        case .medicationPlan:
            guard let item = try? await medicalQueryAPI.retrieveMedicationPlan(id: ref.resourceID) else { return nil }
            return genericContent(
                ref: ref, memberName: memberName,
                title: item.drugName, date: item.startDate,
                organization: item.frequencyText,
                summary: trimmed(item.instructions),
                extraLines: ["\(item.dosePerTime) \(item.doseUnit)"],
                attachments: item.attachments
            )
        case .medicineBox:
            guard let item = try? await medicalQueryAPI.retrieveMedicineBox(id: ref.resourceID) else { return nil }
            return genericContent(
                ref: ref, memberName: memberName,
                title: item.medicineName, date: item.updatedAt,
                organization: item.brandName,
                summary: trimmed(item.notes),
                extraLines: [item.strength],
                attachments: item.attachments
            )
        default:
            return nil
        }
    }

    private static func refreshCompleteData(
        memberID: Int,
        fetchCompleteData: ((Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData)?
    ) async -> SparkMedicalSyncAPI.RemoteMemberCompleteData? {
        guard let fetchCompleteData else { return nil }
        return try? await fetchCompleteData(memberID)
    }

    // MARK: - Builders

    private static func examinationContent(
        ref: HealthResourceRef,
        memberName: String?,
        itemName: String?,
        reportedAt: Date?,
        performedAt: Date?,
        organizationName: String?,
        category: String?,
        subCategory: String?,
        departmentName: String?,
        doctorName: String?,
        findings: String?,
        impression: String?,
        attachments: [SparkMedicalSyncAPI.RemoteManagedFile]?,
        details: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
    ) -> ChatHealthResourcePreviewContent {
        let categoryEnum = ExaminationReportCategory.from(category ?? subCategory)
        return ChatHealthResourcePreviewContent(
            memberName: memberName,
            typeLabel: ref.typeBadge ?? L10n.text(HealthResourceType.examinationReport.localizationKey),
            categoryBadge: L10n.text(categoryEnum.titleKey),
            examinationCategory: categoryEnum,
            title: trimmed(itemName) ?? ref.displayTitle,
            dateText: formatDate(reportedAt ?? performedAt),
            organizationText: trimmed(organizationName),
            summaryText: nil,
            findingsText: trimmed(findings),
            impressionText: trimmed(impression),
            extraLines: [
                trimmed(departmentName).map { String(format: L10n.text("chat.ask_report.preview.department_format"), $0) },
                trimmed(doctorName).map { String(format: L10n.text("chat.ask_report.preview.doctor_format"), $0) }
            ].compactMap { $0 },
            detailGroups: groupedDetails(details),
            attachments: attachments ?? []
        )
    }

    private static func healthExamContent(
        ref: HealthResourceRef,
        memberName: String?,
        institutionName: String?,
        examDate: Date?,
        reportNo: String?,
        summary: String?,
        attachments: [SparkMedicalSyncAPI.RemoteManagedFile]?,
        details: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
    ) -> ChatHealthResourcePreviewContent {
        ChatHealthResourcePreviewContent(
            memberName: memberName,
            typeLabel: ref.typeBadge ?? L10n.text(HealthResourceType.healthExamReport.localizationKey),
            categoryBadge: nil,
            examinationCategory: nil,
            title: trimmed(institutionName) ?? ref.displayTitle,
            dateText: formatDate(examDate),
            organizationText: trimmed(reportNo),
            summaryText: trimmed(summary),
            findingsText: nil,
            impressionText: nil,
            extraLines: [],
            detailGroups: groupedDetails(details),
            attachments: attachments ?? []
        )
    }

    private static func genericContent(
        ref: HealthResourceRef,
        memberName: String?,
        title: String,
        date: Date?,
        organization: String?,
        summary: String?,
        extraLines: [String],
        attachments: [SparkMedicalSyncAPI.RemoteManagedFile]?
    ) -> ChatHealthResourcePreviewContent {
        let type = ref.typedResource ?? .medicalCase
        return ChatHealthResourcePreviewContent(
            memberName: memberName,
            typeLabel: ref.typeBadge ?? L10n.text(type.localizationKey),
            categoryBadge: nil,
            examinationCategory: nil,
            title: title,
            dateText: formatDate(date),
            organizationText: trimmed(organization),
            summaryText: trimmed(summary),
            findingsText: nil,
            impressionText: nil,
            extraLines: extraLines.filter { $0.isEmpty == false },
            detailGroups: [],
            attachments: attachments ?? []
        )
    }

    private static func fallbackContent(ref: HealthResourceRef, memberName: String?) -> ChatHealthResourcePreviewContent {
        let type = ref.typedResource ?? .medicalCase
        return ChatHealthResourcePreviewContent(
            memberName: memberName,
            typeLabel: ref.typeBadge ?? L10n.text(type.localizationKey),
            categoryBadge: nil,
            examinationCategory: nil,
            title: ref.displayTitle,
            dateText: nil,
            organizationText: ref.displaySubtitle.isEmpty ? nil : ref.displaySubtitle,
            summaryText: nil,
            findingsText: nil,
            impressionText: nil,
            extraLines: [],
            detailGroups: [],
            attachments: []
        )
    }

    private static func groupedDetails(
        _ details: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
    ) -> [ChatHealthResourcePreviewDetailGroup] {
        guard let details, details.isEmpty == false else { return [] }
        let sorted = details.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder { return lhs.id < rhs.id }
            return lhs.sortOrder < rhs.sortOrder
        }
        var buckets: [String: [ChatHealthResourcePreviewDetailRow]] = [:]
        var order: [String] = []
        for row in sorted {
            let category = trimmed(row.category).flatMap { $0.isEmpty ? nil : $0 }
                ?? trimmed(row.subCategory)
                ?? L10n.text("chat.ask_report.preview.details_uncategorized")
            if buckets[category] == nil {
                order.append(category)
                buckets[category] = []
            }
            let value = trimmed(row.resultValue) ?? "—"
            let unit = trimmed(row.unit) ?? ""
            let reference = trimmed(row.referenceRange) ?? ""
            var resultLine = unit.isEmpty ? value : "\(value) \(unit)"
            if reference.isEmpty == false {
                resultLine += " (\(reference))"
            }
            let flag = row.flag.trimmingCharacters(in: .whitespacesAndNewlines)
            buckets[category, default: []].append(
                ChatHealthResourcePreviewDetailRow(
                    id: row.id,
                    itemName: row.itemName,
                    resultLine: resultLine,
                    flag: flag,
                    isFlagged: flag.isEmpty == false
                )
            )
        }
        return order.map { key in
            ChatHealthResourcePreviewDetailGroup(id: key, category: key, rows: buckets[key] ?? [])
        }
    }

    private static func symptomLines(
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        caseID: Int
    ) -> [String] {
        let names = (data.symptoms ?? [])
            .filter { $0.medicalCase == caseID }
            .map(\.name)
            .filter { $0.isEmpty == false }
        guard names.isEmpty == false else { return [] }
        return [String(format: L10n.text("chat.ask_report.preview.related_symptoms_format"), names.joined(separator: "、"))]
    }

    private static func planRange(start: Date, end: Date?) -> String {
        let startText = formatDate(start) ?? ""
        let endText = formatDate(end) ?? ""
        if endText.isEmpty { return startText }
        return "\(startText) – \(endText)"
    }

    private static func line(_ key: String, _ value: String?) -> String? {
        guard let text = trimmed(value) else { return nil }
        return String(format: L10n.text(key), text)
    }

    private static func formatDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return dateFormatter.string(from: date)
    }

    private static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}

private extension ChatHealthResourcePreviewContent {
    var hasClinicalBody: Bool {
        trimmedNonEmpty(findingsText) != nil
            || trimmedNonEmpty(impressionText) != nil
            || trimmedNonEmpty(summaryText) != nil
            || detailGroups.isEmpty == false
            || extraLines.isEmpty == false
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
