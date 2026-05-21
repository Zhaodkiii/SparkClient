import Foundation

// MARK: - 附件键
// 结构化医疗卡片键见 ``ChatAttachmentType.structuredHealthCards``（`structured_health_cards`）。

// MARK: - 持久化 Blob（单附件内多类数组，增量 merge）

/// 单条助手消息上挂载的全部结构化医疗卡片（多次 tool call 追加合并）。
struct StructuredHealthCardsBlob: Codable, Equatable, Sendable {
    var extractionFailed: Bool
    var failureMessage: String?
    var medicationPlans: [MedicationChatCardPayload]
    var medicineBoxes: [MedicineBoxChatCardPayload]
    var prescriptions: [PrescriptionChatCardPayload]
    var examReports: [ExamReportChatCardPayload]
    var medicalCases: [MedicalCaseChatCardPayload]

    static var empty: StructuredHealthCardsBlob {
        StructuredHealthCardsBlob()
    }

    init(
        extractionFailed: Bool = false,
        failureMessage: String? = nil,
        medicationPlans: [MedicationChatCardPayload] = [],
        medicineBoxes: [MedicineBoxChatCardPayload] = [],
        prescriptions: [PrescriptionChatCardPayload] = [],
        examReports: [ExamReportChatCardPayload] = [],
        medicalCases: [MedicalCaseChatCardPayload] = []
    ) {
        self.extractionFailed = extractionFailed
        self.failureMessage = failureMessage
        self.medicationPlans = medicationPlans
        self.medicineBoxes = medicineBoxes
        self.prescriptions = prescriptions
        self.examReports = examReports
        self.medicalCases = medicalCases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        extractionFailed = try container.decodeIfPresent(Bool.self, forKey: .extractionFailed) ?? false
        failureMessage = try container.decodeIfPresent(String.self, forKey: .failureMessage)
        medicationPlans =
            try container.decodeIfPresent([MedicationChatCardPayload].self, forKey: .medicationPlans)
            ?? container.decodeIfPresent([MedicationChatCardPayload].self, forKey: .medications)
            ?? []
        medicineBoxes = try container.decodeIfPresent([MedicineBoxChatCardPayload].self, forKey: .medicineBoxes) ?? []
        prescriptions = try container.decodeIfPresent([PrescriptionChatCardPayload].self, forKey: .prescriptions) ?? []
        examReports = try container.decodeIfPresent([ExamReportChatCardPayload].self, forKey: .examReports) ?? []
        medicalCases = try container.decodeIfPresent([MedicalCaseChatCardPayload].self, forKey: .medicalCases) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if extractionFailed { try container.encode(extractionFailed, forKey: .extractionFailed) }
        try container.encodeIfPresent(failureMessage, forKey: .failureMessage)
        if medicationPlans.isEmpty == false { try container.encode(medicationPlans, forKey: .medicationPlans) }
        if medicineBoxes.isEmpty == false { try container.encode(medicineBoxes, forKey: .medicineBoxes) }
        if prescriptions.isEmpty == false { try container.encode(prescriptions, forKey: .prescriptions) }
        if examReports.isEmpty == false { try container.encode(examReports, forKey: .examReports) }
        if medicalCases.isEmpty == false { try container.encode(medicalCases, forKey: .medicalCases) }
    }

    private enum CodingKeys: String, CodingKey {
        case extractionFailed
        case failureMessage
        case medicationPlans
        case medications
        case medicineBoxes
        case prescriptions
        case examReports
        case medicalCases
    }

    static func failed(message: String) -> StructuredHealthCardsBlob {
        StructuredHealthCardsBlob(
            extractionFailed: true,
            failureMessage: message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? L10n.text(
                    "tool.error.structured_health_card.extraction_failed",
                    fallback: "结构化健康卡片生成失败，请稍后重试或补充更完整的病历摘要。"
                )
        )
    }

    var totalCardCount: Int {
        medicationPlans.count + medicineBoxes.count + prescriptions.count + examReports.count + medicalCases.count
    }

    var hasDisplayableCards: Bool {
        extractionFailed || totalCardCount > 0
    }

    mutating func markSaved(_ item: ChatStructuredHealthCardItem) {
        switch item {
        case .medicationPlan:
            if let i = medicationPlans.firstIndex(where: { $0.id == item.id }) {
                medicationPlans[i].isSaved = true
            }
        case .medicineBox:
            if let i = medicineBoxes.firstIndex(where: { $0.id == item.id }) {
                medicineBoxes[i].isSaved = true
            }
        case .prescription:
            if let i = prescriptions.firstIndex(where: { $0.id == item.id }) {
                prescriptions[i].isSaved = true
            }
        case .examReport:
            if let i = examReports.firstIndex(where: { $0.id == item.id }) {
                examReports[i].isSaved = true
            }
        case .medicalCase:
            if let i = medicalCases.firstIndex(where: { $0.id == item.id }) {
                medicalCases[i].isSaved = true
            }
        }
    }

    func contains(item: ChatStructuredHealthCardItem) -> Bool {
        switch item {
        case .medicationPlan:
            medicationPlans.contains { $0.id == item.id }
        case .medicineBox:
            medicineBoxes.contains { $0.id == item.id }
        case .prescription:
            prescriptions.contains { $0.id == item.id }
        case .examReport:
            examReports.contains { $0.id == item.id }
        case .medicalCase:
            medicalCases.contains { $0.id == item.id }
        }
    }

    mutating func updateMember(_ item: ChatStructuredHealthCardItem, memberId: Int?) {
        switch item {
        case .medicationPlan:
            if let i = medicationPlans.firstIndex(where: { $0.id == item.id }) {
                medicationPlans[i].memberId = memberId
            }
        case .medicineBox:
            if let i = medicineBoxes.firstIndex(where: { $0.id == item.id }) {
                medicineBoxes[i].memberId = memberId
            }
        case .prescription:
            if let i = prescriptions.firstIndex(where: { $0.id == item.id }) {
                prescriptions[i].memberId = memberId
            }
        case .examReport:
            if let i = examReports.firstIndex(where: { $0.id == item.id }) {
                examReports[i].memberId = memberId
            }
        case .medicalCase:
            if let i = medicalCases.firstIndex(where: { $0.id == item.id }) {
                medicalCases[i].memberId = memberId
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - 各类卡片载荷（含 draftJson 供保存管线复用）

struct MedicationChatCardPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let draftJson: String
    var isSaved: Bool
    var memberId: Int?
    let ossFileId: Int?
    let displayName: String
    let specification: String?
    let dosageLine: String?

    init(
        id: UUID = UUID(),
        draftJson: String,
        isSaved: Bool,
        memberId: Int?,
        ossFileId: Int?,
        displayName: String,
        specification: String?,
        dosageLine: String?
    ) {
        self.id = id
        self.draftJson = draftJson
        self.isSaved = isSaved
        self.memberId = memberId
        self.ossFileId = ossFileId
        self.displayName = displayName
        self.specification = specification
        self.dosageLine = dosageLine
    }
}

struct MedicineBoxChatCardPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let draftJson: String
    var isSaved: Bool
    var memberId: Int?
    let ossFileId: Int?
    let displayName: String
    let specification: String?

    init(
        id: UUID = UUID(),
        draftJson: String,
        isSaved: Bool,
        memberId: Int?,
        ossFileId: Int?,
        displayName: String,
        specification: String?
    ) {
        self.id = id
        self.draftJson = draftJson
        self.isSaved = isSaved
        self.memberId = memberId
        self.ossFileId = ossFileId
        self.displayName = displayName
        self.specification = specification
    }
}

struct PrescriptionChatCardPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let draftJson: String
    var isSaved: Bool
    var memberId: Int?
    let ossFileId: Int?
    let title: String
    let subtitle: String?

    init(
        id: UUID = UUID(),
        draftJson: String,
        isSaved: Bool,
        memberId: Int?,
        ossFileId: Int?,
        title: String,
        subtitle: String?
    ) {
        self.id = id
        self.draftJson = draftJson
        self.isSaved = isSaved
        self.memberId = memberId
        self.ossFileId = ossFileId
        self.title = title
        self.subtitle = subtitle
    }
}

struct ExamReportChatCardPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let draftJson: String
    var isSaved: Bool
    var memberId: Int?
    let ossFileId: Int?
    let title: String
    let hospital: String?
    let dateText: String?

    init(
        id: UUID = UUID(),
        draftJson: String,
        isSaved: Bool,
        memberId: Int?,
        ossFileId: Int?,
        title: String,
        hospital: String?,
        dateText: String?
    ) {
        self.id = id
        self.draftJson = draftJson
        self.isSaved = isSaved
        self.memberId = memberId
        self.ossFileId = ossFileId
        self.title = title
        self.hospital = hospital
        self.dateText = dateText
    }
}

struct MedicalCaseChatCardPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let draftJson: String
    var isSaved: Bool
    var memberId: Int?
    let ossFileId: Int?
    let title: String
    let diagnosisLine: String?

    init(
        id: UUID = UUID(),
        draftJson: String,
        isSaved: Bool,
        memberId: Int?,
        ossFileId: Int?,
        title: String,
        diagnosisLine: String?
    ) {
        self.id = id
        self.draftJson = draftJson
        self.isSaved = isSaved
        self.memberId = memberId
        self.ossFileId = ossFileId
        self.title = title
        self.diagnosisLine = diagnosisLine
    }
}

enum ChatStructuredHealthCardItem: Equatable, Identifiable, Sendable {
    case medicationPlan(MedicationChatCardPayload)
    case medicineBox(MedicineBoxChatCardPayload)
    case prescription(PrescriptionChatCardPayload)
    case examReport(ExamReportChatCardPayload)
    case medicalCase(MedicalCaseChatCardPayload)

    var id: UUID {
        switch self {
        case .medicationPlan(let card): card.id
        case .medicineBox(let card): card.id
        case .prescription(let card): card.id
        case .examReport(let card): card.id
        case .medicalCase(let card): card.id
        }
    }

    var memberId: Int? {
        switch self {
        case .medicationPlan(let card): card.memberId
        case .medicineBox(let card): card.memberId
        case .prescription(let card): card.memberId
        case .examReport(let card): card.memberId
        case .medicalCase(let card): card.memberId
        }
    }

    var isSaved: Bool {
        switch self {
        case .medicationPlan(let card): card.isSaved
        case .medicineBox(let card): card.isSaved
        case .prescription(let card): card.isSaved
        case .examReport(let card): card.isSaved
        case .medicalCase(let card): card.isSaved
        }
    }

    var draftJson: String {
        switch self {
        case .medicationPlan(let card): card.draftJson
        case .medicineBox(let card): card.draftJson
        case .prescription(let card): card.draftJson
        case .examReport(let card): card.draftJson
        case .medicalCase(let card): card.draftJson
        }
    }

    var rawTrace: String {
        switch self {
        case .medicationPlan(let card): card.displayName
        case .medicineBox(let card): card.displayName
        case .prescription(let card): card.title
        case .examReport(let card): card.title
        case .medicalCase(let card): card.title
        }
    }

    var ossFileId: Int? {
        switch self {
        case .medicationPlan(let card): card.ossFileId
        case .medicineBox(let card): card.ossFileId
        case .prescription(let card): card.ossFileId
        case .examReport(let card): card.ossFileId
        case .medicalCase(let card): card.ossFileId
        }
    }
}

enum ChatStructuredHealthCardAction: Equatable, Sendable {
    case save(blockID: UUID, item: ChatStructuredHealthCardItem)
    case setMember(blockID: UUID, item: ChatStructuredHealthCardItem, Int?)
}

// MARK: - 从抽取输出构建卡片载荷

enum ChatStructuredHealthCardsPayloadBuilder: Sendable {
    private static func nonEmptyTrimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func appendPayloads(
        from output: MedicalDocumentTypedExtractionOutput,
        memberId: Int?,
        ossFileId: Int?
    ) -> StructuredHealthCardsBlob {
        let enc = JSONEncoder.default
        enc.outputFormatting = [.sortedKeys]

        func encode<T: Encodable>(_ value: T) -> String? {
            guard let data = try? enc.encode(value), let s = String(data: data, encoding: .utf8) else { return nil }
            return s
        }

        switch output.typedResult {
        case .medicationPlan(let lines):
            let rows = lines.compactMap { line -> MedicationChatCardPayload? in
                guard let json = encode(line) else { return nil }
                let name = medicationDisplayName(for: line)
                let spec = [line.strength, line.dosageForm]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .joined(separator: " ")
                let dosage = [line.dosePerTime, line.frequencyText]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .joined(separator: " · ")
                return MedicationChatCardPayload(
                    draftJson: json,
                    isSaved: false,
                    memberId: memberId,
                    ossFileId: ossFileId,
                    displayName: name.isEmpty ? fallbackName("common.medication") : name,
                    specification: spec.isEmpty ? nil : spec,
                    dosageLine: dosage.isEmpty ? nil : dosage
                )
            }
            return StructuredHealthCardsBlob(medicationPlans: rows)

        case .medicineBoxes(let boxes):
            let rows = boxes.compactMap { box -> MedicineBoxChatCardPayload? in
                guard let json = encode(box) else { return nil }
                let name = medicineBoxDisplayName(for: box)
                let spec = [box.strength, box.dosageForm, box.medicineType]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .joined(separator: " · ")
                return MedicineBoxChatCardPayload(
                    draftJson: json,
                    isSaved: false,
                    memberId: memberId,
                    ossFileId: ossFileId,
                    displayName: name.isEmpty ? fallbackName("medical_record.medicine_box.title") : name,
                    specification: spec.isEmpty ? nil : spec
                )
            }
            return StructuredHealthCardsBlob(medicineBoxes: rows)

        case .prescription(let draft):
            guard let json = encode(draft) else { return .empty }
            let title = nonEmptyTrimmed(draft.institutionName) ?? fallbackName("common.prescription")
            let sub = nonEmptyTrimmed(draft.diagnosis)
            return StructuredHealthCardsBlob(
                prescriptions: [
                    PrescriptionChatCardPayload(
                        draftJson: json,
                        isSaved: false,
                        memberId: memberId,
                        ossFileId: ossFileId,
                        title: title,
                        subtitle: sub
                    )
                ]
            )

        case .medicalReport(let drafts):
            let rows = drafts.map { d in
                ExamReportChatCardPayload(
                    draftJson: encode(d) ?? "{}",
                    isSaved: false,
                    memberId: memberId,
                    ossFileId: ossFileId,
                    title: nonEmptyTrimmed(d.title) ?? fallbackName("chat.medical_card.exam.title"),
                    hospital: nonEmptyTrimmed(d.hospital),
                    dateText: nonEmptyTrimmed(d.date)
                )
            }
            return StructuredHealthCardsBlob(examReports: rows)

        case .healthExamReport(let draft):
            guard let json = encode(draft) else { return .empty }
            let title = nonEmptyTrimmed(draft.institutionName) ?? fallbackName("chat.medical_card.exam.title")
            return StructuredHealthCardsBlob(
                examReports: [
                    ExamReportChatCardPayload(
                        draftJson: json,
                        isSaved: false,
                        memberId: memberId,
                        ossFileId: ossFileId,
                        title: title,
                        hospital: draft.institutionName,
                        dateText: nonEmptyTrimmed(draft.examDate)
                    )
                ]
            )

        case .caseDocument(let draft):
            guard let json = encode(draft) else { return .empty }
            let title = nonEmptyTrimmed(draft.title) ?? fallbackName("chat.medical_card.case.title")
            let diag = nonEmptyTrimmed(draft.diagnosis)
            return StructuredHealthCardsBlob(
                medicalCases: [
                    MedicalCaseChatCardPayload(
                        draftJson: json,
                        isSaved: false,
                        memberId: memberId,
                        ossFileId: ossFileId,
                        title: title,
                        diagnosisLine: diag
                    )
                ]
            )
        }
    }

    private static func medicationDisplayName(for line: MedicationPlanRecognitionDraft) -> String {
        let candidates = [line.medicineName, line.medicineBox?.medicineName, line.brandName]
        for candidate in candidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false {
                return value
            }
        }
        return ""
    }

    private static func medicineBoxDisplayName(for box: MedicineBoxRecognitionDraft) -> String {
        let candidates = [box.medicineName, box.brandName]
        for candidate in candidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false {
                return value
            }
        }
        return ""
    }

    private static func fallbackName(_ l10nKey: String) -> String {
        L10n.text(l10nKey)
    }
}
