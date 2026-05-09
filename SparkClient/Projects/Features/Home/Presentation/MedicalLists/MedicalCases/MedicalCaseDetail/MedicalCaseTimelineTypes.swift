import Foundation

/// 时间轴「编辑」路由：用于 `NavigationLink` 目标与删除资源。
enum MedicalCaseTimelineEditRoute: Equatable {
    case examination(SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments, category: ExaminationReportCategory)
    case symptom(SparkMedicalSyncAPI.RemoteSymptom)
    case visit(SparkMedicalSyncAPI.RemoteVisit)
    case surgery(SparkMedicalSyncAPI.RemoteSurgery)
    case followUp(SparkMedicalSyncAPI.RemoteFollowUp)

    var deleteResource: (kind: SparkMedicalResourceKind, id: Int)? {
        switch self {
        case .examination(let report, _):
            return (.examinationReports, report.id)
        case .symptom(let row):
            return (.symptoms, row.id)
        case .visit(let row):
            return (.visits, row.id)
        case .surgery(let row):
            return (.surgeries, row.id)
        case .followUp(let row):
            return (.followUps, row.id)
        }
    }
}

/// 单条时间轴事件（病例摘要字符串 + `/complete-data/` 结构化记录）。
struct MedicalCaseTimelineEvent: Identifiable {
    let id: String
    let kind: MedicalCaseTimelineKind
    let title: String
    let detail: String
    let date: Date
    let statusBadgeText: String?

    /// 新药物结构：处方头 + 该处方下的服药计划，或单独的服药计划。
    let prescription: SparkMedicalSyncAPI.RemotePrescription?
    let medicationPlan: SparkMedicalSyncAPI.RemoteMedicationPlan?
    let nestedMedicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    let medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox]

    /// 检查报告卡片。
    let examination: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments?
    let examinationCategory: ExaminationReportCategory?

    let symptom: SparkMedicalSyncAPI.RemoteSymptom?
    let visit: SparkMedicalSyncAPI.RemoteVisit?
    let surgery: SparkMedicalSyncAPI.RemoteSurgery?
    let followUp: SparkMedicalSyncAPI.RemoteFollowUp?

    /// 非空时展示编辑入口（及编辑页内删除）。
    let editRoute: MedicalCaseTimelineEditRoute?

    init(
        id: String,
        kind: MedicalCaseTimelineKind,
        title: String,
        detail: String,
        date: Date,
        statusBadgeText: String?,
        prescription: SparkMedicalSyncAPI.RemotePrescription? = nil,
        medicationPlan: SparkMedicalSyncAPI.RemoteMedicationPlan? = nil,
        nestedMedicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan] = [],
        medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox] = [:],
        examination: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments? = nil,
        examinationCategory: ExaminationReportCategory? = nil,
        symptom: SparkMedicalSyncAPI.RemoteSymptom? = nil,
        visit: SparkMedicalSyncAPI.RemoteVisit? = nil,
        surgery: SparkMedicalSyncAPI.RemoteSurgery? = nil,
        followUp: SparkMedicalSyncAPI.RemoteFollowUp? = nil,
        editRoute: MedicalCaseTimelineEditRoute? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.date = date
        self.statusBadgeText = statusBadgeText
        self.prescription = prescription
        self.medicationPlan = medicationPlan
        self.nestedMedicationPlans = nestedMedicationPlans
        self.medicineBoxesByID = medicineBoxesByID
        self.examination = examination
        self.examinationCategory = examinationCategory
        self.symptom = symptom
        self.visit = visit
        self.surgery = surgery
        self.followUp = followUp
        self.editRoute = editRoute
    }

    func replacingStatusBadge(_ text: String?) -> MedicalCaseTimelineEvent {
        MedicalCaseTimelineEvent(
            id: id,
            kind: kind,
            title: title,
            detail: detail,
            date: date,
            statusBadgeText: text,
            prescription: prescription,
            medicationPlan: medicationPlan,
            nestedMedicationPlans: nestedMedicationPlans,
            medicineBoxesByID: medicineBoxesByID,
            examination: examination,
            examinationCategory: examinationCategory,
            symptom: symptom,
            visit: visit,
            surgery: surgery,
            followUp: followUp,
            editRoute: editRoute
        )
    }
}

extension MedicalCaseTimelineEvent: Hashable {
    static func == (lhs: MedicalCaseTimelineEvent, rhs: MedicalCaseTimelineEvent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum MedicalCaseTimelineEventBuilder {
    static func makeEvents(
        from item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    ) -> [MedicalCaseTimelineEvent] {
        let date = item.updatedAt ?? item.createdAt ?? .now
        let badge = statusBadgeText(for: item.status)
        var events: [MedicalCaseTimelineEvent] = []
        let medicineBoxesByID = Dictionary(uniqueKeysWithValues: (completeData?.medicineBoxes ?? []).map { ($0.id, $0) })
        let plansForCase = (completeData?.medicationPlans ?? []).filter { $0.medicalCase == item.id }
        let prescriptionsForCase = (completeData?.prescriptions ?? []).filter { $0.medicalCase == item.id }
        var nestedPlanIDs = Set<Int>()

        for prescription in prescriptionsForCase {
            let nestedPlans = plansForCase
                .filter { $0.prescription == prescription.id }
                .sorted { $0.startDate > $1.startDate }
            nestedPlanIDs.formUnion(nestedPlans.map(\.id))
            let title = prescription.institutionName.nilIfBlank
                ?? prescription.prescriberName.nilIfBlank
                ?? prescription.prescriptionNo?.nilIfBlank
                ?? L10n.text("common.prescription", fallback: "处方")
            let detail = prescription.diagnosis.nilIfBlank ?? ""
            events.append(
                MedicalCaseTimelineEvent(
                    id: "prescription-\(prescription.id)",
                    kind: .prescription,
                    title: title,
                    detail: detail,
                    date: prescription.prescribedAt ?? prescription.updatedAt,
                    statusBadgeText: nil,
                    prescription: prescription,
                    nestedMedicationPlans: nestedPlans,
                    medicineBoxesByID: medicineBoxesByID
                )
            )
        }

        for plan in plansForCase where nestedPlanIDs.contains(plan.id) == false {
            events.append(
                MedicalCaseTimelineEvent(
                    id: "medication-plan-\(plan.id)",
                    kind: .medication,
                    title: plan.drugName.nilIfBlank ?? L10n.text("common.medication", fallback: "用药"),
                    detail: medicationPlanDetailLine(plan, box: plan.medicineBox.flatMap { medicineBoxesByID[$0] }),
                    date: plan.startDate,
                    statusBadgeText: nil,
                    medicationPlan: plan,
                    medicineBoxesByID: medicineBoxesByID
                )
            )
        }

        let examinationsForCase = (completeData?.examinationReports ?? []).filter { $0.medicalRecord == item.id }
        for report in examinationsForCase {
            let rowDate = report.reportedAt ?? report.performedAt ?? report.updatedAt ?? report.createdAt ?? date
            let category = ExaminationReportCategoryMatcher.category(for: report)
            let title = report.itemName?.nonEmpty
                ?? report.subCategory?.nonEmpty
                ?? report.category?.nonEmpty
                ?? L10n.text(category.titleKey)
            let detail = report.impression?.nonEmpty ?? report.findings?.nonEmpty ?? ""
            events.append(
                MedicalCaseTimelineEvent(
                    id: "examination-\(report.id)",
                    kind: .examination(category),
                    title: title,
                    detail: detail,
                    date: rowDate,
                    statusBadgeText: nil,
                    examination: report,
                    examinationCategory: category,
                    editRoute: .examination(report, category: category)
                )
            )
        }

        let symptomsForCase = (completeData?.symptoms ?? []).filter { $0.medicalCase == item.id }
        for row in symptomsForCase {
            let rowDate = row.startedAt ?? row.updatedAt
            events.append(
                MedicalCaseTimelineEvent(
                    id: "symptom-\(row.id)",
                    kind: .symptom,
                    title: row.name,
                    detail: symptomDetailLine(row),
                    date: rowDate,
                    statusBadgeText: nil,
                    symptom: row,
                    editRoute: .symptom(row)
                )
            )
        }

        let visitsForCase = (completeData?.visits ?? []).filter { $0.medicalCase == item.id }
        for row in visitsForCase {
            let rowDate = row.visitedAt ?? row.updatedAt
            let title = row.department.nilIfBlank
                ?? L10n.text("home.medical.timeline.visit.fallback_title")
            events.append(
                MedicalCaseTimelineEvent(
                    id: "visit-\(row.id)",
                    kind: .visit,
                    title: title,
                    detail: visitDetailLine(row),
                    date: rowDate,
                    statusBadgeText: nil,
                    visit: row,
                    editRoute: .visit(row)
                )
            )
        }

        let surgeriesForCase = (completeData?.surgeries ?? []).filter { $0.medicalCase == item.id }
        for row in surgeriesForCase {
            let rowDate = row.performedAt ?? row.updatedAt
            events.append(
                MedicalCaseTimelineEvent(
                    id: "surgery-\(row.id)",
                    kind: .surgery,
                    title: row.procedureName,
                    detail: surgeryDetailLine(row),
                    date: rowDate,
                    statusBadgeText: nil,
                    surgery: row,
                    editRoute: .surgery(row)
                )
            )
        }

        let followUpsForCase = (completeData?.followUps ?? []).filter { $0.medicalCase == item.id }
        for row in followUpsForCase {
            let rowDate = row.completedAt ?? row.plannedAt ?? row.updatedAt
            let title = row.method.nilIfBlank
                ?? row.status.nilIfBlank
                ?? L10n.text("home.medical.timeline.follow_up.fallback_title")
            events.append(
                MedicalCaseTimelineEvent(
                    id: "follow-up-\(row.id)",
                    kind: .followUp,
                    title: title,
                    detail: followUpDetailLine(row),
                    date: rowDate,
                    statusBadgeText: nil,
                    followUp: row,
                    editRoute: .followUp(row)
                )
            )
        }

        if let meta = metaDetail(from: item) {
            events.append(
                MedicalCaseTimelineEvent(
                    id: "meta",
                    kind: .meta,
                    title: L10n.text("home.medical.case_detail.meta.title"),
                    detail: meta,
                    date: date,
                    statusBadgeText: nil
                )
            )
        }

        var sorted = events.sorted { $0.date > $1.date }
        if let badge, sorted.isEmpty == false {
            let firstId = sorted[0].id
            sorted = sorted.map { $0.id == firstId ? $0.replacingStatusBadge(badge) : $0.replacingStatusBadge(nil) }
        }
        return sorted
    }

    private static func symptomDetailLine(_ s: SparkMedicalSyncAPI.RemoteSymptom) -> String {
        [s.severity.nilIfBlank, s.bodyPart.nilIfBlank, s.notes.nilIfBlank].compactMap { $0 }.joined(separator: " · ")
    }

    private static func visitDetailLine(_ v: SparkMedicalSyncAPI.RemoteVisit) -> String {
        [v.doctorName.nilIfBlank, v.visitNo.nilIfBlank, v.notes.nilIfBlank].compactMap { $0 }.joined(separator: " · ")
    }

    private static func surgeryDetailLine(_ s: SparkMedicalSyncAPI.RemoteSurgery) -> String {
        [s.surgeon.nilIfBlank, s.site.nilIfBlank, s.notes.nilIfBlank].compactMap { $0 }.joined(separator: " · ")
    }

    private static func followUpDetailLine(_ f: SparkMedicalSyncAPI.RemoteFollowUp) -> String {
        [f.outcome.nilIfBlank, f.nextAction.nilIfBlank].compactMap { $0 }.joined(separator: " · ")
    }

    private static func medicationPlanDetailLine(
        _ plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        box: SparkMedicalSyncAPI.RemoteMedicineBox?
    ) -> String {
        [
            plan.dosePerTime.nilIfBlank,
            plan.frequencyText.nilIfBlank,
            plan.reminderTimes.map(\.time).joined(separator: ", ").nilIfBlank,
            box.map { "\($0.remainingQuantity.formatted(.number.precision(.fractionLength(0...2)))) \($0.unit)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private static func metaDetail(from item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> String? {
        var parts: [String] = []
        if let hospital = item.hospitalName?.nonEmpty {
            parts.append("\(L10n.text("home.medical.case_detail.meta.hospital"))：\(hospital)")
        }
        if let recordType = item.recordType?.nonEmpty {
            parts.append("\(L10n.text("home.medical.case_detail.meta.record_type"))：\(recordType)")
        }
        if let age = item.ageAtVisit {
            parts.append("\(L10n.text("home.medical.case_detail.meta.age"))：\(age)")
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: "\n")
    }

    private static func statusBadgeText(for status: Int?) -> String? {
        guard let status else { return nil }
        let cardStatus: MedicalCaseCardStatus
        switch status {
        case 0:
            cardStatus = .pendingDiagnosis
        case 1:
            cardStatus = .inTreatment
        case 2:
            cardStatus = .review
        case 3:
            cardStatus = .chronicManagement
        case 4:
            cardStatus = .cured
        default:
            cardStatus = .unknown
        }
        guard cardStatus != .empty else { return nil }
        return cardStatus.displayName
    }
}

/// 与 `MedicalCaseDetailPage` 私有枚举对齐，供时间轴 builder 生成状态文案。
private enum MedicalCaseCardStatus {
    case chronicManagement
    case inTreatment
    case review
    case cured
    case pendingDiagnosis
    case empty
    case unknown

    var displayName: String {
        switch self {
        case .empty:
            return ""
        case .chronicManagement:
            return L10n.text("home.medical.list.medical_case.status.chronic_management")
        case .inTreatment:
            return L10n.text("home.medical.list.medical_case.status.in_treatment")
        case .review:
            return L10n.text("home.medical.list.medical_case.status.review")
        case .cured:
            return L10n.text("home.medical.list.medical_case.status.cured")
        case .pendingDiagnosis:
            return L10n.text("home.medical.list.medical_case.status.pending_diagnosis")
        case .unknown:
            return L10n.text("home.medical.list.medical_case.status.unknown")
        }
    }
}

/// 检查报告分类匹配器：根据报告字段推断分类。
private enum ExaminationReportCategoryMatcher {
    static func category(for report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> ExaminationReportCategory {
        if let direct = directCategory(from: report) {
            return direct
        }

        let haystack = [
            report.itemName,
            report.category,
            report.subCategory,
            report.findings,
            report.impression,
            report.extra?["summary"]
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if ["影像", "超声", "ct", "mr", "mri", "放射", "x线", "b超", "彩超"].contains(where: { haystack.contains($0) }) {
            return .imaging
        }
        if haystack.contains("病理") || haystack.contains("pathology") {
            return .pathology
        }
        return .laboratory
    }

    private static func directCategory(from report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> ExaminationReportCategory? {
        let candidates = [report.category, report.subCategory]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        for candidate in candidates {
            switch candidate {
            case "laboratory", "lab", "实验室检查", "检验", "化验":
                return .laboratory
            case "imaging", "image", "影像", "影像学检查":
                return .imaging
            case "pathology", "病理", "病理检查":
                return .pathology
            default:
                continue
            }
        }
        return nil
    }
}
