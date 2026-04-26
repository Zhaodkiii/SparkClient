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

/// 聊天结构化健康卡片载荷构建器
/// 作用：将服务端/本地抽取的医疗文档数据，转换成聊天界面可展示的结构化卡片数据模型
enum ChatStructuredHealthCardsPayloadBuilder: Sendable {
    /// 辅助方法：去除字符串首尾空格/换行，空值返回 nil
    private static func nonEmptyTrimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 抽取失败时生成占位病历卡片（用于OCR/识别失败场景）
    /// 生成一条可手动编辑的占位病历卡片，对齐健康模块交互行为
    /// - Parameters:
    ///   - memberID: 成员ID
    ///   - reportType: 报告类型（用于错误提示）
    ///   - ossFileId: 上传的文件ID
    /// - Returns: 结构化卡片Blob数据
    static func extractionFailureBlob(memberID: Int, reportType: String, ossFileId: Int?) -> StructuredHealthCardsBlob {
        // 多语言：抽取失败标题/说明
        let title = L10n.text("chat.medical_card.extraction_failed.title")
        let summary = L10n.text("chat.medical_card.extraction_failed.body")
        
        // 构建空的病历草稿模型（仅填充提示文案）
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
        
        // JSON编码草稿模型
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys] // 按键排序，保证格式稳定
        guard let data = try? enc.encode(draft), let json = String(data: data, encoding: .utf8) else {
            return .empty // 编码失败返回空Blob
        }
        
        // 构建并返回包含错误占位卡片的结构化Blob
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

    /// 核心方法：从医疗文档抽取结果，生成聊天结构化卡片载荷
    /// - Parameters:
    ///   - output: 医疗文档抽取输出结果
    ///   - memberID: 成员ID
    ///   - ossFileId: OSS文件ID（可选）
    /// - Returns: 聊天界面可用的结构化卡片Blob
    static func appendPayloads(
        from output: MedicalDocumentTypedExtractionOutput,
        memberID: Int,
        ossFileId: Int?
    ) -> StructuredHealthCardsBlob {
        // JSON编码器配置：按键排序，保证输出稳定
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        
        // 通用编码方法：将模型转为JSON字符串
        func encode<T: Encodable>(_ value: T) -> String? {
            guard let data = try? enc.encode(value), let s = String(data: data, encoding: .utf8) else { return nil }
            return s
        }

        // 根据抽取结果类型，生成对应类型的卡片
        switch output.typedResult {
        // MARK: 用药卡片
        case .medication(let lines):
            let rows = lines.compactMap { line -> MedicationChatCardPayload? in
                guard let json = encode(line) else { return nil }
                // 获取药品名称
                let name = medicationDisplayName(for: line)
                // 拼接规格：剂量 + 剂型
                let spec = [line.strength, line.dosageForm]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .joined(separator: " ")
                // 拼接用法用量：每次剂量 + 服用频率
                let dosage = [line.dosePerTime, line.frequencyText ?? line.frequencyCode]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .joined(separator: " · ")
                
                // 构建用药卡片
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
            // 返回仅包含用药卡片的Blob
            return StructuredHealthCardsBlob(
                medications: rows,
                prescriptions: [],
                examReports: [],
                medicalCases: []
            )

        // MARK: 处方卡片
        case .prescription(let draft):
            guard let json = encode(draft) else {
                return .empty
            }
            // 处方标题：医院名称 / 默认标题
            let title = nonEmptyTrimmed(draft.institutionName)
                ?? fallbackName("chat.medical_card.prescription.title")
            // 处方副标题：诊断信息
            let sub = nonEmptyTrimmed(draft.diagnosis)
            
            // 返回仅包含处方卡片的Blob
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

        // MARK: 医疗报告卡片（检查/检验报告）
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

        // MARK: 健康体检报告卡片
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

        // MARK: 病历卡片
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

    /// 获取用药卡片显示名称（优先级：药品名 -> 通用名 -> 商品名）
    private static func medicationDisplayName(for line: MedicationRecognitionDraft) -> String {
        let candidates = [line.drugName, line.genericName, line.brandName]
        for c in candidates {
            if let s = c?.trimmingCharacters(in: .whitespacesAndNewlines), s.isEmpty == false { return s }
        }
        return ""
    }

    /// 获取默认标题（多语言兜底文案）
    private static func fallbackName(_ l10nKey: String) -> String {
        L10n.text(l10nKey)
    }
}
