import Foundation

enum ChatAskReportTimelineMapper {
    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func map(_ data: SparkMedicalSyncAPI.RemoteMemberCompleteData) -> AskReportMappedTimeline {
        let memberID = data.memberId
        var leaves: [ChatSelectableHealthSource] = []

        for item in data.healthExamReports ?? [] {
            leaves.append(makeHealthExam(item, memberID: memberID))
        }
        for item in data.examinationReports ?? [] {
            leaves.append(makeExamination(item, memberID: memberID))
        }
        for item in data.prescriptions ?? [] {
            leaves.append(makePrescription(item, memberID: memberID))
        }
        for item in data.medicationPlans ?? [] {
            leaves.append(makeMedicationPlan(item, memberID: memberID))
        }
        for item in data.medicineBoxes ?? [] {
            leaves.append(makeMedicineBox(item, memberID: memberID))
        }
        for item in data.todayMedicationRecords ?? [] {
            leaves.append(makeMedicationRecord(item, memberID: memberID, plans: data.medicationPlans ?? []))
        }
        if let summary = data.medicationSummary {
            leaves.append(makeMedicationSummary(summary, memberID: memberID))
        }
        for item in data.symptoms ?? [] {
            leaves.append(makeSymptom(item, memberID: memberID))
        }
        for item in data.visits ?? [] {
            leaves.append(makeVisit(item, memberID: memberID))
        }
        for item in data.surgeries ?? [] {
            leaves.append(makeSurgery(item, memberID: memberID))
        }
        for item in data.followUps ?? [] {
            leaves.append(makeFollowUp(item, memberID: memberID))
        }

        let caseIDs = Set((data.medicalCases ?? []).map(\.id))
        var childrenByCase: [Int: [ChatSelectableHealthSource]] = [:]
        var orphans: [ChatSelectableHealthSource] = []

        for leaf in leaves {
            if let caseID = leaf.medicalCaseID, caseIDs.contains(caseID) {
                childrenByCase[caseID, default: []].append(leaf)
            } else {
                orphans.append(leaf)
            }
        }

        var groups: [AskReportTimelineRow] = []
        for caseItem in data.medicalCases ?? [] {
            let children = sortLeaves(childrenByCase[caseItem.id] ?? [])
            let parent = makeMedicalCase(caseItem, memberID: memberID, children: children)
            groups.append(.medicalCaseGroup(parent))
        }

        let orphanRows = sortLeaves(orphans).map { AskReportTimelineRow.leaf($0) }
        let allRows = sortRows(groups + orphanRows)

        let medicalCaseRows = allRows.compactMap { row -> AskReportTimelineRow? in
            if case .medicalCaseGroup = row { return row }
            return nil
        }

        let healthExamRows = leaves
            .filter { $0.resourceType == .healthExamReport }
            .sorted(by: leafSort)
            .map { AskReportTimelineRow.leaf($0) }

        let examinationRows = leaves
            .filter { $0.resourceType == .examinationReport }
            .sorted(by: leafSort)
            .map { AskReportTimelineRow.leaf($0) }

        let medicationRows = leaves
            .filter { selectedTabMedicationTypes.contains($0.resourceType) }
            .sorted(by: leafSort)
            .map { AskReportTimelineRow.leaf($0) }

        var selectable: [ChatSelectableHealthSource] = []
        for row in allRows {
            switch row {
            case .medicalCaseGroup(let parent):
                selectable.append(parent)
                selectable.append(contentsOf: parent.children)
            case .leaf(let leaf):
                selectable.append(leaf)
            }
        }
        for row in healthExamRows + examinationRows + medicationRows {
            if selectable.contains(where: { $0.selectionKey == row.selectableSource.selectionKey }) == false {
                selectable.append(row.selectableSource)
            }
        }

        return AskReportMappedTimeline(
            allRows: allRows,
            medicalCaseRows: medicalCaseRows,
            healthExamRows: healthExamRows,
            examinationRows: examinationRows,
            medicationRows: medicationRows,
            allSelectableSources: selectable
        )
    }

    static func makeHealthResourceRef(from source: ChatSelectableHealthSource) -> HealthResourceRef {
        HealthResourceRef(
            type: source.resourceType,
            resourceID: source.resourceID,
            memberID: source.memberID,
            displayTitle: source.title,
            displaySubtitle: source.subtitle ?? "",
            typeBadge: L10n.text(source.resourceType.localizationKey)
        )
    }

    private static let selectedTabMedicationTypes: Set<HealthResourceType> = [
        .medicineBox, .prescription, .medicationPlan, .medicationRecord, .medicationSummary
    ]

    // MARK: - Medical case

    private static func makeMedicalCase(
        _ item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary,
        memberID: Int,
        children: [ChatSelectableHealthSource]
    ) -> ChatSelectableHealthSource {
        let title = nonEmpty(item.title, fallback: L10n.text("chat.ask_report.resource_type.medical_case"))
        let subtitle = nonEmpty(item.diagnosisSummary, fallback: nonEmpty(item.hospitalName))
        let summary = formattedDate(item.updatedAt ?? item.createdAt)
        let symptomNames = (item.symptoms ?? []).joined(separator: " ")
        let medicationNames = (item.medications ?? []).joined(separator: " ")
        let searchText = joinSearch(
            title, subtitle, item.hospitalName, item.diagnosisSummary,
            symptomNames, medicationNames
        )
        return ChatSelectableHealthSource(
            id: key(.medicalCase, item.id, memberID),
            resourceType: .medicalCase,
            resourceID: item.id,
            memberID: memberID,
            occurredAt: item.updatedAt ?? item.createdAt,
            title: title,
            subtitle: subtitle,
            summary: summary,
            badges: [],
            searchText: searchText,
            medicalCaseID: item.id,
            attachmentCount: item.attachments?.count,
            children: children
        )
    }

    // MARK: - Leaves

    private static func makeHealthExam(
        _ item: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments,
        memberID: Int
    ) -> ChatSelectableHealthSource {
        let title = nonEmpty(item.institutionName, fallback: L10n.text("chat.ask_report.resource_type.health_exam_report"))
        let dateText = formattedDate(item.examDate)
        let subtitle = joinNonEmpty([item.reportNo, dateText], separator: " · ")
        let summary = nonEmpty(item.summary)
        let abnormalCount = item.medExamDetails?.filter { $0.flag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count ?? 0
        var badges: [String] = []
        if abnormalCount > 0 {
            badges.append(String(format: L10n.text("chat.ask_report.sheet.badge.abnormal_format"), abnormalCount))
        }
        let attachmentCount = item.attachments?.count ?? 0
        if attachmentCount > 0 {
            badges.append(String(format: L10n.text("chat.ask_report.message_card.attachment_count_format"), attachmentCount))
        }
        let searchText = joinSearch(
            title, subtitle, summary, item.reportNo, item.institutionName,
            item.extra?["summary"], attachmentNames(item.attachments)
        )
        return ChatSelectableHealthSource(
            id: key(.healthExamReport, item.id, memberID),
            resourceType: .healthExamReport,
            resourceID: item.id,
            memberID: memberID,
            occurredAt: item.examDate ?? item.updatedAt,
            title: title,
            subtitle: subtitle.isEmpty ? dateText : subtitle,
            summary: summary.isEmpty ? nil : summary,
            badges: badges,
            searchText: searchText,
            medicalCaseID: nil,
            attachmentCount: attachmentCount,
            children: []
        )
    }

    private static func makeExamination(
        _ item: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments,
        memberID: Int
    ) -> ChatSelectableHealthSource {
        let category = ExaminationReportCategory.category(for: item)
        let title = nonEmpty(item.itemName, fallback: L10n.text("chat.ask_report.resource_type.examination_report"))
        let dateText = formattedDate(item.reportedAt ?? item.performedAt)
        let subtitle = joinNonEmpty([item.organizationName, dateText], separator: " · ")
        let findings = item.findings?.nonEmpty ?? ""
        let impression = item.impression?.nonEmpty ?? ""
        let summary = joinNonEmpty([findings, impression], separator: " · ")
        let attachmentCount = item.attachments?.count ?? 0
        var badges = [L10n.text(category.titleKey)]
        if attachmentCount > 0 {
            badges.append(String(format: L10n.text("chat.ask_report.message_card.attachment_count_format"), attachmentCount))
        }
        let searchText = joinSearch(
            title, subtitle, summary, item.category, item.subCategory,
            item.organizationName, item.departmentName, item.doctorName,
            findings, impression, attachmentNames(item.attachments)
        )
        return ChatSelectableHealthSource(
            id: key(.examinationReport, item.id, memberID),
            resourceType: .examinationReport,
            resourceID: item.id,
            memberID: memberID,
            occurredAt: item.reportedAt ?? item.performedAt ?? item.updatedAt,
            title: title,
            subtitle: subtitle,
            summary: summary.isEmpty ? nil : summary,
            badges: badges,
            searchText: searchText,
            medicalCaseID: linkedMedicalCaseID(item.medicalRecord),
            attachmentCount: attachmentCount,
            children: []
        )
    }

    private static func makePrescription(
        _ item: SparkMedicalSyncAPI.RemotePrescription,
        memberID: Int
    ) -> ChatSelectableHealthSource {
        let title = nonEmpty(item.diagnosis, fallback: L10n.text("chat.ask_report.resource_type.prescription"))
        let subtitle = joinNonEmpty([item.institutionName, formattedDate(item.prescribedAt)], separator: " · ")
        let searchText = joinSearch(title, subtitle, item.institutionName, item.prescriberName, item.prescriptionNo)
        return ChatSelectableHealthSource(
            id: key(.prescription, item.id, memberID),
            resourceType: .prescription,
            resourceID: item.id,
            memberID: memberID,
            occurredAt: item.prescribedAt ?? item.updatedAt,
            title: title,
            subtitle: subtitle,
            summary: nil,
            badges: [],
            searchText: searchText,
            medicalCaseID: linkedMedicalCaseID(item.medicalCase),
            attachmentCount: item.attachments?.count,
            children: []
        )
    }

    private static func makeMedicationPlan(
        _ item: SparkMedicalSyncAPI.RemoteMedicationPlan,
        memberID: Int
    ) -> ChatSelectableHealthSource {
        let title = nonEmpty(item.drugName, fallback: L10n.text("chat.ask_report.resource_type.medication_plan"))
        let dose = joinNonEmpty([item.dosePerTime, item.doseUnit], separator: " ")
        let subtitle = joinNonEmpty([dose, item.frequencyText, planDateRange(item)], separator: " · ")
        let searchText = joinSearch(title, subtitle, item.drugName, item.dosePerTime, item.frequencyText, item.instructions)
        return ChatSelectableHealthSource(
            id: key(.medicationPlan, item.id, memberID),
            resourceType: .medicationPlan,
            resourceID: item.id,
            memberID: memberID,
            occurredAt: item.startDate,
            title: title,
            subtitle: subtitle,
            summary: nil,
            badges: [],
            searchText: searchText,
            medicalCaseID: linkedMedicalCaseID(item.medicalCase),
            attachmentCount: item.attachments?.count,
            children: []
        )
    }

    private static func makeMedicineBox(
        _ item: SparkMedicalSyncAPI.RemoteMedicineBox,
        memberID: Int
    ) -> ChatSelectableHealthSource {
        let title = nonEmpty(item.medicineName, fallback: L10n.text("chat.ask_report.resource_type.medicine_box"))
        let stock = item.totalQuantity.map { String(format: "%g", $0) } ?? ""
        let subtitle = joinNonEmpty([item.brandName, item.strength, stock, formattedDate(item.expireDate)], separator: " · ")
        let searchText = joinSearch(title, subtitle, item.medicineName, item.brandName, item.notes)
        return ChatSelectableHealthSource(
            id: key(.medicineBox, item.id, memberID),
            resourceType: .medicineBox,
            resourceID: item.id,
            memberID: memberID,
            occurredAt: item.updatedAt,
            title: title,
            subtitle: subtitle,
            summary: item.notes.nonEmpty,
            badges: [],
            searchText: searchText,
            medicalCaseID: nil,
            attachmentCount: item.attachments?.count,
            children: []
        )
    }

    private static func makeMedicationRecord(
        _ item: SparkMedicalSyncAPI.RemoteMedicationRecord,
        memberID: Int,
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    ) -> ChatSelectableHealthSource {
        let planName = plans.first(where: { $0.id == item.plan })?.drugName
        let title = nonEmpty(planName, fallback: L10n.text("chat.ask_report.resource_type.medication_record"))
        let subtitle = "\(item.status) · \(formattedDate(item.scheduledAt))"
        let searchText = joinSearch(title, subtitle, item.status, item.notes, planName)
        return ChatSelectableHealthSource(
            id: key(.medicationRecord, item.id, memberID),
            resourceType: .medicationRecord,
            resourceID: item.id,
            memberID: memberID,
            occurredAt: item.scheduledAt,
            title: title,
            subtitle: subtitle,
            summary: nil,
            badges: [item.status],
            searchText: searchText,
            medicalCaseID: nil,
            attachmentCount: nil,
            children: []
        )
    }

    private static func makeMedicationSummary(
        _ summary: SparkMedicalSyncAPI.RemoteMedicationSummary,
        memberID: Int
    ) -> ChatSelectableHealthSource {
        let title = L10n.text("chat.ask_report.resource_type.medication_summary")
        let subtitle = String(
            format: L10n.text("chat.ask_report.medication_summary.subtitle_format"),
            summary.todayTaken,
            summary.todayTotal
        )
        return ChatSelectableHealthSource(
            id: key(.medicationSummary, memberID, memberID),
            resourceType: .medicationSummary,
            resourceID: memberID,
            memberID: memberID,
            occurredAt: Date(),
            title: title,
            subtitle: subtitle,
            summary: nil,
            badges: [],
            searchText: joinSearch(title, subtitle),
            medicalCaseID: nil,
            attachmentCount: nil,
            children: []
        )
    }

    private static func makeSymptom(
        _ item: SparkMedicalSyncAPI.RemoteSymptom,
        memberID: Int
    ) -> ChatSelectableHealthSource {
        let title = nonEmpty(item.name, fallback: L10n.text("chat.ask_report.resource_type.symptom"))
        let subtitle = joinNonEmpty([item.severity, formattedDate(item.startedAt)], separator: " · ")
        let searchText = joinSearch(title, subtitle, item.name, item.severity, item.notes)
        return ChatSelectableHealthSource(
            id: key(.symptom, item.id, memberID),
            resourceType: .symptom,
            resourceID: item.id,
            memberID: memberID,
            occurredAt: item.startedAt ?? item.updatedAt,
            title: title,
            subtitle: subtitle,
            summary: item.notes.nonEmpty,
            badges: [],
            searchText: searchText,
            medicalCaseID: linkedMedicalCaseID(item.medicalCase),
            attachmentCount: nil,
            children: []
        )
    }

    private static func makeVisit(
        _ item: SparkMedicalSyncAPI.RemoteVisit,
        memberID: Int
    ) -> ChatSelectableHealthSource {
        let title = nonEmpty(item.department, fallback: L10n.text("chat.ask_report.resource_type.visit"))
        let subtitle = joinNonEmpty([item.doctorName, formattedDate(item.visitedAt)], separator: " · ")
        let searchText = joinSearch(title, subtitle, item.department, item.doctorName, item.visitNo, item.notes)
        return ChatSelectableHealthSource(
            id: key(.visit, item.id, memberID),
            resourceType: .visit,
            resourceID: item.id,
            memberID: memberID,
            occurredAt: item.visitedAt ?? item.updatedAt,
            title: title,
            subtitle: subtitle,
            summary: item.notes.nonEmpty,
            badges: [],
            searchText: searchText,
            medicalCaseID: linkedMedicalCaseID(item.medicalCase),
            attachmentCount: nil,
            children: []
        )
    }

    private static func makeSurgery(
        _ item: SparkMedicalSyncAPI.RemoteSurgery,
        memberID: Int
    ) -> ChatSelectableHealthSource {
        let title = nonEmpty(item.procedureName, fallback: L10n.text("chat.ask_report.resource_type.surgery"))
        let subtitle = joinNonEmpty([item.surgeon, formattedDate(item.performedAt)], separator: " · ")
        let searchText = joinSearch(title, subtitle, item.procedureName, item.surgeon, item.notes)
        return ChatSelectableHealthSource(
            id: key(.surgery, item.id, memberID),
            resourceType: .surgery,
            resourceID: item.id,
            memberID: memberID,
            occurredAt: item.performedAt ?? item.updatedAt,
            title: title,
            subtitle: subtitle,
            summary: item.notes.nonEmpty,
            badges: [],
            searchText: searchText,
            medicalCaseID: linkedMedicalCaseID(item.medicalCase),
            attachmentCount: nil,
            children: []
        )
    }

    private static func makeFollowUp(
        _ item: SparkMedicalSyncAPI.RemoteFollowUp,
        memberID: Int
    ) -> ChatSelectableHealthSource {
        let title = L10n.text("chat.ask_report.resource_type.follow_up")
        let subtitle = joinNonEmpty([item.outcome, formattedDate(item.plannedAt ?? item.completedAt)], separator: " · ")
        let searchText = joinSearch(title, subtitle, item.outcome, item.method, item.nextAction, item.status)
        return ChatSelectableHealthSource(
            id: key(.followUp, item.id, memberID),
            resourceType: .followUp,
            resourceID: item.id,
            memberID: memberID,
            occurredAt: item.completedAt ?? item.plannedAt ?? item.updatedAt,
            title: title,
            subtitle: subtitle,
            summary: item.nextAction.nonEmpty,
            badges: [],
            searchText: searchText,
            medicalCaseID: linkedMedicalCaseID(item.medicalCase),
            attachmentCount: nil,
            children: []
        )
    }

    private static func linkedMedicalCaseID(_ caseID: Int?) -> Int? {
        guard let caseID, caseID > 0 else { return nil }
        return caseID
    }

    private static func linkedMedicalCaseID(_ caseID: Int) -> Int? {
        linkedMedicalCaseID(Optional(caseID))
    }

    // MARK: - Sort

    private static func sortLeaves(_ leaves: [ChatSelectableHealthSource]) -> [ChatSelectableHealthSource] {
        leaves.sorted(by: leafSort)
    }

    private static func leafSort(_ lhs: ChatSelectableHealthSource, _ rhs: ChatSelectableHealthSource) -> Bool {
        let ld = lhs.occurredAt ?? .distantPast
        let rd = rhs.occurredAt ?? .distantPast
        if Calendar.current.isDate(ld, inSameDayAs: rd) == false {
            return ld > rd
        }
        return typePriority(lhs.resourceType) < typePriority(rhs.resourceType)
    }

    private static func sortRows(_ rows: [AskReportTimelineRow]) -> [AskReportTimelineRow] {
        rows.sorted { lhs, rhs in
            let ld = lhs.occurredAt ?? .distantPast
            let rd = rhs.occurredAt ?? .distantPast
            if Calendar.current.isDate(ld, inSameDayAs: rd) == false {
                return ld > rd
            }
            return typePriority(lhs.selectableSource.resourceType) < typePriority(rhs.selectableSource.resourceType)
        }
    }

    private static func typePriority(_ type: HealthResourceType) -> Int {
        switch type {
        case .medicalCase: return 0
        case .examinationReport, .healthExamReport: return 1
        case .visit, .followUp, .surgery, .symptom: return 2
        case .prescription, .medicationPlan, .medicineBox, .medicationRecord, .medicationSummary: return 3
        }
    }

    // MARK: - Helpers

    private static func key(_ type: HealthResourceType, _ id: Int, _ memberID: Int) -> String {
        "\(type.rawValue):\(id):\(memberID)"
    }

    private static func nonEmpty(_ primary: String?, fallback: String = "") -> String {
        let trimmed = primary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty == false { return trimmed }
        let fallbackTrimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackTrimmed.isEmpty ? "—" : fallbackTrimmed
    }

    private static func formattedDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return displayDateFormatter.string(from: date)
    }

    private static func planDateRange(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> String {
        let start = formattedDate(plan.startDate)
        let end = formattedDate(plan.endDate)
        if end.isEmpty { return start }
        return "\(start) – \(end)"
    }

    private static func joinNonEmpty(_ parts: [String?], separator: String) -> String {
        parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: separator)
    }

    private static func joinSearch(_ parts: String?...) -> String {
        parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .lowercased()
    }

    private static func attachmentNames(_ files: [SparkMedicalSyncAPI.RemoteManagedFile]?) -> String? {
        guard let files, files.isEmpty == false else { return nil }
        return files.compactMap(\.originalName).joined(separator: " ")
    }
}
