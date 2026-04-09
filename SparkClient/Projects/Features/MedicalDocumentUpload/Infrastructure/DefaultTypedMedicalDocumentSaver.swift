import Foundation

/// 默认实现的【医疗文档结构化结果保存器】
/// 核心职责：将 AI 抽取完成的结构化医疗数据，调用后端 API 保存到服务器
/// 遵循 TypedMedicalDocumentSaving 协议 + Sendable 保证跨异步/线程安全
struct DefaultTypedMedicalDocumentSaver: TypedMedicalDocumentSaving, Sendable {
    // MARK: - 依赖
    /// 医疗工作流 API 客户端（负责真正调用后端接口）
    let workflowAPI: SparkMedicalWorkflowAPI
    /// 日志器
    let logger: Logger

    // MARK: - 初始化
    /// 初始化保存器
    /// - Parameters:
    ///   - workflowAPI: 后端 API 实例
    ///   - logger: 日志实例，默认控制台日志
    init(
        workflowAPI: SparkMedicalWorkflowAPI,
        logger: Logger = ConsoleLogger()
    ) {
        self.workflowAPI = workflowAPI
        self.logger = logger
    }

    // MARK: - 对外核心方法：保存抽取结果
    /// 保存【类型化医疗文档抽取结果】到后端
    /// - Parameter output: 抽取完成的结构化输出（包含病例/体检/报告/处方/用药等）
    /// - Returns: 保存回执（记录ID、保存时间、是否成功）
    /// - Throws: API 调用失败、参数错误
    func save(output: MedicalDocumentTypedExtractionOutput) async throws -> MedicalDocumentSaveReceipt {
        // 会员ID（用户归属）
        let memberID = output.envelope.memberID
        // 当前时间（用于兜底日期）
        let now = Date()
        // 后端返回的记录ID（最终要返回给上层）
        let recordID: Int

        // 根据文档类型，分别调用不同的保存接口
        switch output.typedResult {
        // 1. 保存病例文档
        case .caseDocument(let draft):
            recordID = try await workflowAPI.saveCase(
                .init(
                    member: memberID,                // 会员ID
                    recordType: "case_document",      // 记录类型：病例
                    status: 2,                       // 状态：2=已完成
                    title: draft.title,               // 标题
                    diagnosisSummary: draft.diagnosis ?? draft.summary, // 诊断摘要
                    extra: ["source": "typed_upload"] // 来源标记：类型化上传
                )
            )

        // 2. 保存体检报告
        case .healthExamReport(let draft):
            // 构建体检报告完整提交数据
            let payload = buildHealthExamPayload(
                memberID: memberID,
                draft: draft,
                rawOCRText: output.envelope.rawOCRText,
                now: now
            )
            // 打印调试日志：体检项数量、报告号、摘要长度
            logger.debug(
                "体检保存请求准备完成，draftItems=\(draft.items.count), details=\(payload.details.count), reportNo=\(payload.reportNo), summaryLength=\(payload.summary?.count ?? 0)",
                category: "medical_upload"
            )
            // 调用 API 保存并获取记录ID
            recordID = try await workflowAPI.saveHealthExam(payload)

        // 3. 保存医疗检查报告
        case .medicalReport(let drafts):
            let payloads = try buildMedicalReportPayloads(memberID: memberID, drafts: drafts, now: now)
            var savedRecordID: Int?
            for payload in payloads {
                savedRecordID = try await workflowAPI.saveMedicalReport(payload)
            }
            recordID = savedRecordID ?? 0

        // 4. 保存处方单
        case .prescription(let draft):
            // 构建处方下的药品列表
            let medications = buildPrescriptionMedicationPayloads(
                memberID: memberID,
                draft: draft
            )
            let prescribedAt = Date.parseOrNow(draft.prescribedAt, defaultDate: now).toISO8601()
            // 调用保存处方 API
            recordID = try await workflowAPI.savePrescription(
                .init(
                    member: memberID,
                    medicalCase: nil,                 // 关联病例ID（无）
                    prescriberName: draft.prescriberName ?? "", // 开方医生
                    institutionName: draft.institutionName ?? "", // 医疗机构
                    prescribedAt: prescribedAt, // 开方时间
                    diagnosis: draft.diagnosis ?? "", // 诊断
                    batchNo: draft.batchNo ?? "",     // 处方号
                    status: nil,
                    auditorName: "",
                    auditedAt: nil,
                    extra: ["source": "typed_upload"],
                    medications: medications           // 药品列表
                )
            )

        // 5. 保存用药记录
        case .medication(let draft):
            recordID = try await workflowAPI.saveMedication(
                .init(
                    member: memberID,
                    batch: 0,
                    genericName: draft.drugName,       // 药品通用名
                    brandName: "",
                    drugName: draft.drugName,          // 药品名称
                    dosageForm: "",
                    strength: draft.dosage ?? "",      // 规格/剂量
                    route: "",
                    dosePerTime: draft.dosage ?? "",   // 每次剂量
                    doseValue: nil,
                    doseUnit: "",
                    frequencyCode: "",
                    period: "",
                    timesPerPeriod: nil,
                    frequencyText: draft.frequencyText ?? "", // 用法用量文字
                    durationDays: draft.durationDays,         // 服用天数
                    instructions: draft.instructions ?? "",   // 服用说明
                    reminderEnabled: false,
                    reminderTimes: [],
                    sortOrder: 0,
                    extra: ["source": "typed_upload"]
                )
            )
        }

        // 打印日志：保存完成
        logger.info("typed 结果保存完成，memberID=\(memberID)", category: "medical_upload")

        // 返回保存回执
        return MedicalDocumentSaveReceipt(recordID: recordID, savedAt: now, isSuccess: true)
    }
}

// MARK: - Date 扩展工具
private extension Date {
    /// 转为 年月日 字符串（yyyy-MM-dd）
    func toDateOnly() -> String { MedicalDateCoding.encodeDateOnly(self) }
    /// 转为 ISO8601 标准时间字符串
    func toISO8601() -> String { MedicalDateCoding.encodeISO8601(self) }
}

// MARK: - 私有工具方法（各类文档构建提交参数）
private extension DefaultTypedMedicalDocumentSaver {
    // MARK: 构建体检报告保存参数
    func buildHealthExamPayload(
        memberID: Int,
        draft: HealthExamRecognitionDraft,
        rawOCRText: String,
        now: Date
    ) -> SparkMedicalWorkflowAPI.HealthExamSavePayload {
        // 获取最终确定的机构名称（优先 draft，兜底从 OCR 识别）
        let institutionName = resolvedHealthExamInstitutionName(draft: draft, rawOCRText: rawOCRText) ?? ""
        let examDate = Date.parseOrNow(draft.examDate, defaultDate: now)
        
        return .init(
            member: memberID,
            institutionName: institutionName,    // 体检机构
            reportNo: draft.reportNo ?? "",      // 报告编号
            examDate: examDate.toDateOnly(), // 体检日期
            examType: parseHealthExamType(draft.examType), // 体检类型（常规/入职/专项…）
            summary: draft.summary,              // 体检总结
            source: 2,                           // 来源：2=AI上传
            rawOCR: ["text": rawOCRText],        // 原始OCR文本
            status: 1,                           // 状态：1=正常
            extra: ["source": "typed_upload"],
            details: buildHealthExamDetails(draft: draft, defaultDate: examDate.toISO8601()) // 体检明细项
        )
    }

    // MARK: 解析体检机构名称（优先 draft，没有就从 OCR 里找关键词）
    func resolvedHealthExamInstitutionName(
        draft: HealthExamRecognitionDraft,
        rawOCRText: String
    ) -> String? {
        // 优先使用抽取到的机构名
        if let institutionName = draft.institutionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           institutionName.isEmpty == false {
            return institutionName
        }
        
        // 没有则从 OCR 文本里按行查找
        let lines = rawOCRText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && $0.hasPrefix("===") == false } // 过滤文件分隔行
        
        // 关键词匹配医院/体检/健康等
        let keywords = ["医院", "体检", "健康", "门诊", "中心", "clinic", "hospital", "health"]
        return lines.first { line in
            let normalized = line.lowercased()
            return keywords.contains { normalized.contains($0.lowercased()) }
        } ?? lines.first // 兜底：返回第一行有效文本
    }

    // MARK: 把文字类型的体检类型 → 后端枚举数字
    func parseHealthExamType(_ rawValue: String?) -> Int {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              rawValue.isEmpty == false else {
            return 1 // 默认常规体检
        }
        
        switch rawValue {
        case "1", "routine", "常规", "常规体检":
            return 1
        case "2", "onboarding", "入职", "入职体检":
            return 2
        case "3", "special", "专项", "专项体检":
            return 3
        case "4", "senior", "老年", "老年体检":
            return 4
        default:
            return 1
        }
    }

    // MARK: 构建体检明细项（转为后端需要的格式）
    func buildHealthExamDetails(
        draft: HealthExamRecognitionDraft,
        defaultDate: String
    ) -> [SparkMedicalWorkflowAPI.MedicalReportDetailPayload] {
        draft.items.enumerated().map { index, item in
            // 排序：优先 item.sortOrder，兜底用 index
            let sortOrder: Int = {
                guard let s = item.sortOrder else { return index }
                return s == 0 ? index : s
            }()

            let defaultResultAt = Date.parseOrNow(defaultDate)
            let resultAt = Date.parseOrNow(item.resultAt, defaultDate: defaultResultAt).toISO8601()
            let payload = SparkMedicalWorkflowAPI.MedicalReportDetailPayload(
                category: item.category,
                subCategory: item.subCategory ?? "",
                itemName: item.itemName,
                itemCode: item.itemCode ?? "",
                resultValue: item.resultValue,
                unit: item.unit ?? "",
                referenceRange: item.referenceRange ?? "",
                flag: item.flag ?? "",
                resultAt: resultAt,
                modality: item.modality ?? "",
                bodyPart: item.bodyPart ?? "",
                diagnosis: item.diagnosis ?? "",
                extra: item.extra ?? [:],
                sortOrder: sortOrder
            )
            return payload
        }
    }

    // MARK: 构建处方里的药品列表
    func buildPrescriptionMedicationPayloads(
        memberID: Int,
        draft: PrescriptionRecognitionDraft
    ) -> [SparkMedicalWorkflowAPI.MedicationSavePayload] {
        draft.medications.enumerated().map { index, item in
            SparkMedicalWorkflowAPI.MedicationSavePayload(
                member: memberID,
                batch: 0,
                genericName: item.name,
                brandName: "",
                drugName: item.name,
                dosageForm: "",
                strength: item.specification ?? "",
                route: "",
                dosePerTime: item.dosage ?? "",
                doseValue: nil,
                doseUnit: "",
                frequencyCode: "",
                period: "",
                timesPerPeriod: nil,
                frequencyText: item.frequency ?? "",
                durationDays: parseDurationDays(item.duration), // 解析服用天数
                instructions: item.instructions ?? "",
                reminderEnabled: false,
                reminderTimes: [],
                sortOrder: index,
                extra: ["source": "typed_upload"]
            )
        }
    }

    // MARK: 从文字中解析服用天数（如 "7天" → 7）
    func parseDurationDays(_ durationText: String?) -> Int? {
        guard let durationText else { return nil }
        // 直接是数字
        if let numeric = Int(durationText) { return numeric }
        // 提取字符串里的所有数字
        let digits = durationText.filter(\.isNumber)
        return Int(digits)
    }

    // MARK: 构建医疗报告保存参数
    func buildMedicalReportPayloads(
        memberID: Int,
        drafts: [MedicalReportRecognitionDraft],
        now: Date
    ) throws -> [SparkMedicalWorkflowAPI.MedicalReportSavePayload] {
        guard drafts.isEmpty == false else {
            throw NSError(
                domain: "DefaultTypedMedicalDocumentSaver",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "medical report drafts is empty"]
            )
        }

        return drafts.map { draft in
            // 报告时间
            let date = MedicalDateCoding.decodeDateOnlyOrDefaultNow(draft.date, defaultDate: now)
            let dateText = date.toISO8601()
            // 报告类型
            let reportType = draft.reportType ?? "medical_report"
            // 报告内容（优先详情，兜底标题）
            let findingsText = draft.content.isEmpty ? draft.title : draft.content
            
            // 构建报告明细
            let detailRows: [SparkMedicalWorkflowAPI.MedicalReportDetailPayload] = draft.details.enumerated().map { index, row in
                let sortOrder: Int = {
                    guard let s = row.sortOrder else { return index }
                    return s == 0 ? index : s
                }()

                let defaultResultAt = Date.parseOrNow(dateText)
                let resultAt = Date.parseOrNow(row.resultAt, defaultDate: defaultResultAt).toISO8601()
                let payload = SparkMedicalWorkflowAPI.MedicalReportDetailPayload(
                    category: row.category,
                    subCategory: row.subCategory ?? "",
                    itemName: row.itemName,
                    itemCode: row.itemCode ?? "",
                    resultValue: row.resultValue,
                    unit: row.unit ?? "",
                    referenceRange: row.referenceRange ?? "",
                    flag: row.flag ?? "",
                    resultAt: resultAt,
                    modality: row.modality ?? "",
                    bodyPart: row.bodyPart ?? "",
                    diagnosis: row.diagnosis ?? "",
                    extra: row.extra ?? [:],
                    sortOrder: sortOrder
                )
                return payload
            }
            
            // 返回最终构建的报告提交结构体
            return SparkMedicalWorkflowAPI.MedicalReportSavePayload(
                member: memberID,
                medicalCase: nil,
                reportType: reportType,
                category: reportType,
                subCategory: "",
                itemName: draft.title,
                performedAt: dateText,
                reportedAt: dateText,
                organizationName: draft.hospital,
                departmentName: "",
                doctorName: draft.doctor ?? "",
                findings: findingsText,
                impression: findingsText,
                modality: "",
                bodyPart: "",
                diagnosis: "",
                details: detailRows
            )
        }
    }

}
