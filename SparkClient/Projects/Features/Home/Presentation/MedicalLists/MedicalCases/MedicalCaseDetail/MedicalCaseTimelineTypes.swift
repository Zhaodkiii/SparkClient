import Foundation

/// 时间轴「编辑」路由：用于 `NavigationLink` 目标与删除资源。
enum MedicalCaseTimelineEditRoute: Equatable {
    case prescription(SparkMedicalSyncAPI.RemotePrescriptionBatchComplete)
    case standaloneMedication(SparkMedicalSyncAPI.RemoteMedication)

    var deleteResource: (kind: SparkMedicalResourceKind, id: Int)? {
        switch self {
        case .prescription(let batch):
            return (.prescriptionBatches, batch.id)
        case .standaloneMedication(let medication):
            return (.medications, medication.id)
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

    /// 处方卡片：头信息与嵌套药品。
    let prescription: SparkMedicalSyncAPI.RemotePrescriptionBatchComplete?
    let nestedMedications: [SparkMedicalSyncAPI.RemoteMedication]?

    /// 非空时展示编辑入口（及编辑页内删除）。
    let editRoute: MedicalCaseTimelineEditRoute?

    init(
        id: String,
        kind: MedicalCaseTimelineKind,
        title: String,
        detail: String,
        date: Date,
        statusBadgeText: String?,
        prescription: SparkMedicalSyncAPI.RemotePrescriptionBatchComplete? = nil,
        nestedMedications: [SparkMedicalSyncAPI.RemoteMedication]? = nil,
        editRoute: MedicalCaseTimelineEditRoute? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.date = date
        self.statusBadgeText = statusBadgeText
        self.prescription = prescription
        self.nestedMedications = nestedMedications
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
            nestedMedications: nestedMedications,
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

        let batchesForCase = (completeData?.prescriptionBatches ?? []).filter { $0.medicalCase == item.id }
        let idsInCaseNested = Set(batchesForCase.flatMap { $0.medications ?? [] }.map(\.id))
        let caseBatchIds = Set(batchesForCase.map(\.id))

        for batch in batchesForCase {
            let rowDate = batch.prescribedAt ?? batch.updatedAt ?? batch.createdAt ?? date
            let meds = batch.medications ?? []
            let title = batch.institutionName?.nonEmpty
                ?? (batch.diagnosis ?? "").nilIfBlank
                ?? L10n.text("home.medical.list.fallback.prescription_title")
            let detail = (batch.diagnosis ?? "").nilIfBlank ?? ""
            events.append(
                MedicalCaseTimelineEvent(
                    id: "prescription-\(batch.id)",
                    kind: .prescription,
                    title: title,
                    detail: detail,
                    date: rowDate,
                    statusBadgeText: nil,
                    prescription: batch,
                    nestedMedications: meds,
                    editRoute: .prescription(batch)
                )
            )
        }

        let standaloneForCase = standaloneMedications(for: item, completeData: completeData, idsInCaseNested: idsInCaseNested, caseBatchIds: caseBatchIds)
        for medication in standaloneForCase {
            let title = medication.drugName.nilIfBlank ?? medication.genericName.nilIfBlank ?? L10n.text("home.medical.list.fallback.medication_name")
            let detail = medicationLineSummary(medication)
            events.append(
                MedicalCaseTimelineEvent(
                    id: "medication-\(medication.id)",
                    kind: .medication,
                    title: title,
                    detail: detail,
                    date: medication.updatedAt,
                    statusBadgeText: nil,
                    prescription: nil,
                    nestedMedications: nil,
                    editRoute: .standaloneMedication(medication)
                )
            )
        }

        let remoteMedicationNames = medicationDisplayNames(from: batchesForCase, standalone: standaloneForCase)
        for (index, symptom) in (item.symptoms ?? []).enumerated() {
            events.append(
                MedicalCaseTimelineEvent(
                    id: "symptom-\(index)-\(symptom.hashValue)",
                    kind: .symptom,
                    title: symptom,
                    detail: "",
                    date: date,
                    statusBadgeText: nil
                )
            )
        }

        if let medications = item.medications {
            for (index, medicationTitle) in medications.enumerated() {
                let normalized = normalizeMedicationName(medicationTitle)
                if remoteMedicationNames.contains(normalized) { continue }
                events.append(
                    MedicalCaseTimelineEvent(
                        id: "medication-str-\(index)-\(medicationTitle.hashValue)",
                        kind: .medication,
                        title: medicationTitle,
                        detail: "",
                        date: date,
                        statusBadgeText: nil
                    )
                )
            }
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

    private static func standaloneMedications(
        for item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        idsInCaseNested: Set<Int>,
        caseBatchIds: Set<Int>
    ) -> [SparkMedicalSyncAPI.RemoteMedication] {
        guard let standalone = completeData?.standaloneMedications else { return [] }
        return standalone.filter { med in
            if idsInCaseNested.contains(med.id) { return false }
            return caseBatchIds.contains(med.batch)
        }
    }

    private static func medicationDisplayNames(
        from batches: [SparkMedicalSyncAPI.RemotePrescriptionBatchComplete],
        standalone: [SparkMedicalSyncAPI.RemoteMedication]
    ) -> Set<String> {
        var names = Set<String>()
        for m in batches.flatMap({ $0.medications ?? [] }) + standalone {
            if let n = m.drugName.nilIfBlank.map(normalizeMedicationName) {
                names.insert(n)
            }
            if let n = m.genericName.nilIfBlank.map(normalizeMedicationName) {
                names.insert(n)
            }
        }
        return names
    }

    private static func normalizeMedicationName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func medicationLineSummary(_ m: SparkMedicalSyncAPI.RemoteMedication) -> String {
        let parts = [m.strength.nilIfBlank, m.frequencyText.nilIfBlank, m.dosePerTime.nilIfBlank].compactMap { $0 }
        return parts.joined(separator: " · ")
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
