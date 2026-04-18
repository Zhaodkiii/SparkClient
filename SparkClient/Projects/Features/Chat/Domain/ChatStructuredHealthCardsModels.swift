import Foundation

// MARK: - 附件键
// 结构化医疗卡片键见 ``ChatAttachmentType.structuredHealthCards``（`structured_health_cards`）。

// MARK: - 持久化 Blob（单附件内四类数组，增量 merge）

/// 单条助手消息上挂载的全部结构化医疗卡片（多次 tool call 追加合并）。
struct StructuredHealthCardsBlob: Codable, Equatable, Sendable {
    var medications: [MedicationChatCardPayload]
    var prescriptions: [PrescriptionChatCardPayload]
    var examReports: [ExamReportChatCardPayload]
    var medicalCases: [MedicalCaseChatCardPayload]

    static var empty: StructuredHealthCardsBlob {
        StructuredHealthCardsBlob(
            medications: [],
            prescriptions: [],
            examReports: [],
            medicalCases: []
        )
    }

    mutating func markMedicationSaved(id: UUID) {
        if let i = medications.firstIndex(where: { $0.id == id }) {
            medications[i].isSaved = true
        }
    }

    mutating func markPrescriptionSaved(id: UUID) {
        if let i = prescriptions.firstIndex(where: { $0.id == id }) {
            prescriptions[i].isSaved = true
        }
    }

    mutating func markExamReportSaved(id: UUID) {
        if let i = examReports.firstIndex(where: { $0.id == id }) {
            examReports[i].isSaved = true
        }
    }

    mutating func markMedicalCaseSaved(id: UUID) {
        if let i = medicalCases.firstIndex(where: { $0.id == id }) {
            medicalCases[i].isSaved = true
        }
    }
}

// MARK: - 各类卡片载荷（含 draftJSON 供保存管线复用）

struct MedicationChatCardPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// 单行药品草稿，与 ``SaveTypedMedicalDocumentUseCase`` / 组合 API 一致。
    let draftJSON: String
    var isSaved: Bool
    let memberID: Int
    let ossFileId: Int?
    let displayName: String
    let specification: String?
    let dosageLine: String?

    init(
        id: UUID = UUID(),
        draftJSON: String,
        isSaved: Bool,
        memberID: Int,
        ossFileId: Int?,
        displayName: String,
        specification: String?,
        dosageLine: String?
    ) {
        self.id = id
        self.draftJSON = draftJSON
        self.isSaved = isSaved
        self.memberID = memberID
        self.ossFileId = ossFileId
        self.displayName = displayName
        self.specification = specification
        self.dosageLine = dosageLine
    }
}

struct PrescriptionChatCardPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let draftJSON: String
    var isSaved: Bool
    let memberID: Int
    let ossFileId: Int?
    let title: String
    let subtitle: String?

    init(
        id: UUID = UUID(),
        draftJSON: String,
        isSaved: Bool,
        memberID: Int,
        ossFileId: Int?,
        title: String,
        subtitle: String?
    ) {
        self.id = id
        self.draftJSON = draftJSON
        self.isSaved = isSaved
        self.memberID = memberID
        self.ossFileId = ossFileId
        self.title = title
        self.subtitle = subtitle
    }
}

struct ExamReportChatCardPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let draftJSON: String
    var isSaved: Bool
    let memberID: Int
    let ossFileId: Int?
    let title: String
    let hospital: String?
    let dateText: String?

    init(
        id: UUID = UUID(),
        draftJSON: String,
        isSaved: Bool,
        memberID: Int,
        ossFileId: Int?,
        title: String,
        hospital: String?,
        dateText: String?
    ) {
        self.id = id
        self.draftJSON = draftJSON
        self.isSaved = isSaved
        self.memberID = memberID
        self.ossFileId = ossFileId
        self.title = title
        self.hospital = hospital
        self.dateText = dateText
    }
}

struct MedicalCaseChatCardPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let draftJSON: String
    var isSaved: Bool
    let memberID: Int
    let ossFileId: Int?
    let title: String
    let diagnosisLine: String?

    init(
        id: UUID = UUID(),
        draftJSON: String,
        isSaved: Bool,
        memberID: Int,
        ossFileId: Int?,
        title: String,
        diagnosisLine: String?
    ) {
        self.id = id
        self.draftJSON = draftJSON
        self.isSaved = isSaved
        self.memberID = memberID
        self.ossFileId = ossFileId
        self.title = title
        self.diagnosisLine = diagnosisLine
    }
}

// MARK: - 从抽取输出构建卡片载荷

enum ChatStructuredHealthCardsPayloadBuilder: Sendable {
    private static func nonEmptyTrimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 抽取失败时仍插入一条可编辑占位病例卡片，提示用户手动完善（对齐 HealthClient 行为）。
    static func extractionFailureBlob(memberID: Int, reportType: String, ossFileId: Int?) -> StructuredHealthCardsBlob {
        let title = L10n.text("chat.medical_card.extraction_failed.title")
        let summary = L10n.text("chat.medical_card.extraction_failed.body")
        let draft = CaseRecognitionDraft(
            title: title,
            summary: summary,
            diagnosis: nil,
            hospitalName: nil,
            ageAtVisit: nil,
            occurredAt: nil,
            symptom: nil,
            visit: nil,
            surgery: nil,
            followUps: nil,
            prescriptionBatches: nil,
            examinationReports: nil
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(draft), let json = String(data: data, encoding: .utf8) else {
            return .empty
        }
        let sub = "report_type=\(reportType)"
        return StructuredHealthCardsBlob(
            medications: [],
            prescriptions: [],
            examReports: [],
            medicalCases: [
                MedicalCaseChatCardPayload(
                    draftJSON: json,
                    isSaved: false,
                    memberID: memberID,
                    ossFileId: ossFileId,
                    title: title,
                    diagnosisLine: sub
                )
            ]
        )
    }

    static func appendPayloads(
        from output: MedicalDocumentTypedExtractionOutput,
        memberID: Int,
        ossFileId: Int?
    ) -> StructuredHealthCardsBlob {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        func encode<T: Encodable>(_ value: T) -> String? {
            guard let data = try? enc.encode(value), let s = String(data: data, encoding: .utf8) else { return nil }
            return s
        }

        switch output.typedResult {
        case .medication(let lines):
            let rows = lines.compactMap { line -> MedicationChatCardPayload? in
                guard let json = encode(line) else { return nil }
                let name = medicationDisplayName(for: line)
                let spec = [line.strength, line.dosageForm]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .joined(separator: " ")
                let dosage = [line.dosePerTime, line.frequencyText ?? line.frequencyCode]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .joined(separator: " · ")
                return MedicationChatCardPayload(
                    draftJSON: json,
                    isSaved: false,
                    memberID: memberID,
                    ossFileId: ossFileId,
                    displayName: name.isEmpty ? fallbackName("chat.medical_card.medication.untitled") : name,
                    specification: spec.isEmpty ? nil : spec,
                    dosageLine: dosage.isEmpty ? nil : dosage
                )
            }
            return StructuredHealthCardsBlob(
                medications: rows,
                prescriptions: [],
                examReports: [],
                medicalCases: []
            )

        case .prescription(let draft):
            guard let json = encode(draft) else {
                return .empty
            }
            let title = nonEmptyTrimmed(draft.institutionName)
                ?? fallbackName("chat.medical_card.prescription.title")
            let sub = nonEmptyTrimmed(draft.diagnosis)
            return StructuredHealthCardsBlob(
                medications: [],
                prescriptions: [
                    PrescriptionChatCardPayload(
                        draftJSON: json,
                        isSaved: false,
                        memberID: memberID,
                        ossFileId: ossFileId,
                        title: title,
                        subtitle: sub
                    )
                ],
                examReports: [],
                medicalCases: []
            )

        case .medicalReport(let drafts):
            let rows = drafts.map { d in
                ExamReportChatCardPayload(
                    draftJSON: encode(d) ?? "{}",
                    isSaved: false,
                    memberID: memberID,
                    ossFileId: ossFileId,
                    title: nonEmptyTrimmed(d.title)
                        ?? fallbackName("chat.medical_card.exam.title"),
                    hospital: nonEmptyTrimmed(d.hospital),
                    dateText: nonEmptyTrimmed(d.date)
                )
            }
            return StructuredHealthCardsBlob(
                medications: [],
                prescriptions: [],
                examReports: rows,
                medicalCases: []
            )

        case .healthExamReport(let draft):
            guard let json = encode(draft) else { return .empty }
            let title = nonEmptyTrimmed(draft.institutionName)
                ?? fallbackName("chat.medical_card.exam.title")
            return StructuredHealthCardsBlob(
                medications: [],
                prescriptions: [],
                examReports: [
                    ExamReportChatCardPayload(
                        draftJSON: json,
                        isSaved: false,
                        memberID: memberID,
                        ossFileId: ossFileId,
                        title: title,
                        hospital: draft.institutionName,
                        dateText: nonEmptyTrimmed(draft.examDate)
                    )
                ],
                medicalCases: []
            )

        case .caseDocument(let draft):
            guard let json = encode(draft) else { return .empty }
            let title = nonEmptyTrimmed(draft.title)
                ?? fallbackName("chat.medical_card.case.title")
            let diag = nonEmptyTrimmed(draft.diagnosis)
            return StructuredHealthCardsBlob(
                medications: [],
                prescriptions: [],
                examReports: [],
                medicalCases: [
                    MedicalCaseChatCardPayload(
                        draftJSON: json,
                        isSaved: false,
                        memberID: memberID,
                        ossFileId: ossFileId,
                        title: title,
                        diagnosisLine: diag
                    )
                ]
            )
        }
    }

    private static func medicationDisplayName(for line: MedicationRecognitionDraft) -> String {
        let candidates = [line.drugName, line.genericName, line.brandName]
        for c in candidates {
            if let s = c?.trimmingCharacters(in: .whitespacesAndNewlines), s.isEmpty == false { return s }
        }
        return ""
    }

    private static func fallbackName(_ l10nKey: String) -> String {
        L10n.text(l10nKey)
    }
}
