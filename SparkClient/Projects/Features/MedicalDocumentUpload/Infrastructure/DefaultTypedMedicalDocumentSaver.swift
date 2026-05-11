import Foundation

/// 默认实现的【医疗文档结构化结果保存器】
/// 核心职责：将 AI 抽取完成的结构化医疗数据，调用后端 API 保存到服务器
/// 遵循 TypedMedicalDocumentSaving 协议 + Sendable 保证跨异步/线程安全
struct DefaultTypedMedicalDocumentSaver: TypedMedicalDocumentSaving, Sendable {
    // MARK: - 依赖
    /// 医疗工作流 API 客户端（负责真正调用后端接口）
    let workflowAPI: SparkMedicalWorkflowAPI
    /// 组合创建 API 客户端（用于一次性创建完整医疗记录）
    let combinedAPI: SparkCombinedMedicalCreateAPI
    /// 日志器
    let logger: Logger

    // MARK: - 初始化
    /// 初始化保存器
    /// - Parameters:
    ///   - workflowAPI: 后端工作流 API 实例
    ///   - combinedAPI: 后端组合创建 API 实例
    ///   - logger: 日志实例，默认控制台日志
    init(
        workflowAPI: SparkMedicalWorkflowAPI,
        combinedAPI: SparkCombinedMedicalCreateAPI,
        logger: Logger = ConsoleLogger()
    ) {
        self.workflowAPI = workflowAPI
        self.combinedAPI = combinedAPI
        self.logger = logger
    }

    // MARK: - 对外核心方法：保存抽取结果
    /// 保存【类型化医疗文档抽取结果】到后端
    /// - Parameter output: 抽取完成的结构化输出（包含病例/体检/报告/处方/用药等）
    /// - Returns: 保存回执（记录ID、保存时间、是否成功）
    /// - Throws: API 调用失败、参数错误
    func save(output: MedicalDocumentTypedExtractionOutput) async throws -> MedicalDocumentSaveReceipt {
        // 会员ID（用户归属）
        guard let memberID = output.envelope.memberID else {
            throw NSError(
                domain: "DefaultTypedMedicalDocumentSaver",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: L10n.text("chat.medical_card.error.no_member")]
            )
        }
        // 当前时间（用于兜底日期）
        let now = Date()

        // 根据文档类型，分别调用不同的保存接口
        switch output.typedResult {
        // 1. 保存病例文档（使用组合创建 API）
        case .caseDocument(let draft):
            let receipt = try await saveCombinedCase(
                memberID: memberID,
                draft: draft,
                envelope: output.envelope,
                now: now
            )
            return receipt

        // 2. 保存体检报告（专用工作流接口 `workflows/health-exams/save/`，不经过组合创建）
        case .healthExamReport(let draft):
            let receipt = try await saveHealthExamReport(
                memberID: memberID,
                draft: draft,
                envelope: output.envelope,
                now: now
            )
            return receipt

        // 3. 保存医疗检查报告（使用独立新增 API，不创建病例）
        case .medicalReport(let drafts):
            let receipt = try await saveStandaloneMedicalReports(
                memberID: memberID,
                drafts: drafts,
                envelope: output.envelope,
                now: now
            )
            return receipt

        case .prescription(let draft):
            return try await savePrescriptionWithPlans(
                memberID: memberID,
                draft: draft,
                envelope: output.envelope,
                now: now
            )

        case .medicationPlan(let lines):
            return try await saveMedicationPlans(
                memberID: memberID,
                drafts: lines,
                envelope: output.envelope,
                now: now
            )
        case .medicineBoxes(let boxes):
            return try await saveMedicineBoxes(
                memberID: memberID,
                drafts: boxes,
                now: now
            )
        }
    }

}

private extension DefaultTypedMedicalDocumentSaver {
    func saveMedicationPlans(
        memberID: Int,
        drafts: [MedicationPlanRecognitionDraft],
        envelope: MedicalDocumentRecognitionEnvelope,
        now: Date
    ) async throws -> MedicalDocumentSaveReceipt {
        let payload = SparkMedicalWorkflowAPI.MedicationPlanBundleSavePayload(
            member: memberID,
            medicalCase: nil,
            prescriptionID: nil,
            prescription: nil,
            items: buildMedicationPlanBundleItems(drafts, now: now),
            fileIds: extractSourceFileIds(from: envelope)
        )
        let id = try await workflowAPI.saveMedicationPlanBundle(payload)
        return MedicalDocumentSaveReceipt(recordID: id, savedAt: now, isSuccess: true)
    }

    func savePrescriptionWithPlans(
        memberID: Int,
        draft: PrescriptionRecognitionDraft,
        envelope: MedicalDocumentRecognitionEnvelope,
        now: Date
    ) async throws -> MedicalDocumentSaveReceipt {
        let prescription = SparkMedicalWorkflowAPI.PrescriptionPayload(
            medicalCase: draft.medicalCase,
            prescriberName: draft.prescriberName,
            institutionName: draft.institutionName,
            prescribedAt: draft.prescribedAt,
            diagnosis: draft.diagnosis,
            prescriptionNo: draft.batchNo,
            status: draft.status ?? "active",
            extra: mergeTypedUploadExtra(draft.extra)
        )
        let payload = SparkMedicalWorkflowAPI.MedicationPlanBundleSavePayload(
            member: memberID,
            medicalCase: draft.medicalCase,
            prescriptionID: nil,
            prescription: prescription,
            items: buildMedicationPlanBundleItems(draft.medications ?? [], now: now),
            fileIds: extractSourceFileIds(from: envelope)
        )
        let id = try await workflowAPI.saveMedicationPlanBundle(payload)
        return MedicalDocumentSaveReceipt(recordID: id, savedAt: now, isSuccess: true)
    }

    func saveMedicineBoxes(
        memberID: Int,
        drafts: [MedicineBoxRecognitionDraft],
        now: Date
    ) async throws -> MedicalDocumentSaveReceipt {
        var savedIDs: [Int] = []
        for draft in drafts {
            let payload = MedicineBoxCreatePayload(
                member: memberID,
                medicineName: resolvedMedicineBoxName(draft),
                medicineType: draft.medicineType?.nilIfBlank,
                brandName: draft.brandName?.nilIfBlank ?? "",
                dosageForm: draft.dosageForm?.nilIfBlank ?? "",
                strength: draft.strength?.nilIfBlank ?? "",
                doseUnit: draft.doseUnit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                totalQuantity: draft.totalQuantity.flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) },
                expireDate: draft.expireDate?.nilIfBlank,
                notes: draft.notes?.nilIfBlank ?? "",
                extra: mergeTypedUploadExtra(draft.extra)
            )
            let saved = try await workflowAPI.create(
                SparkMedicalSyncAPI.RemoteMedicineBox.self,
                kind: .medicineBoxes,
                body: payload
            )
            savedIDs.append(saved.id)
        }
        guard let firstID = savedIDs.first else {
            throw NSError(
                domain: "DefaultTypedMedicalDocumentSaver",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "未识别到可保存的药箱药品"]
            )
        }
        return MedicalDocumentSaveReceipt(recordID: firstID, savedAt: now, isSuccess: true)
    }

    func resolvedMedicineBoxName(_ draft: MedicineBoxRecognitionDraft) -> String {
        if let value = draft.medicineName?.nilIfBlank { return value }
        if let value = draft.brandName?.nilIfBlank { return value }
        return "未命名药品"
    }

    func buildMedicationPlanBundleItems(
        _ drafts: [MedicationPlanRecognitionDraft],
        now: Date
    ) -> [SparkMedicalWorkflowAPI.MedicationPlanBundleItemPayload] {
        drafts.enumerated().map { index, draft in
            let box = draft.medicineBox
            let medicineName = box?.medicineName?.nilIfBlank
                ?? draft.medicineName?.nilIfBlank
                ?? draft.brandName?.nilIfBlank
                ?? "未命名药品"
            let doseUnit = draft.doseUnit?.nilIfBlank ?? box?.doseUnit?.nilIfBlank ?? "片"
            let dosePerTime = draft.dosePerTime?.nilIfBlank
                ?? [draft.doseValue?.nilIfBlank, doseUnit].compactMap { $0 }.joined(separator: " ")
                .nilIfBlank
                ?? "按医嘱"
            let startDate = draft.startDate?.nilIfBlank ?? now.toDateOnly()
            let frequencyType = normalizedFrequencyType(draft.frequencyType)
            return SparkMedicalWorkflowAPI.MedicationPlanBundleItemPayload(
                medicineBox: SparkMedicalWorkflowAPI.MedicineBoxPayload(
                    medicineType: box?.medicineType?.nilIfBlank ?? draft.medicineType?.nilIfBlank,
                    medicineName: medicineName,
                    brandName: box?.brandName?.nilIfBlank ?? draft.brandName?.nilIfBlank ?? "",
                    dosageForm: box?.dosageForm?.nilIfBlank ?? draft.dosageForm?.nilIfBlank ?? "",
                    strength: box?.strength?.nilIfBlank ?? draft.strength?.nilIfBlank ?? "",
                    doseUnit: doseUnit,
                    totalQuantity: box?.totalQuantity?.nilIfBlank ?? draft.totalQuantity?.nilIfBlank,
                    expireDate: box?.expireDate?.nilIfBlank ?? draft.expireDate?.nilIfBlank,
                    notes: box?.notes?.nilIfBlank ?? "",
                    extra: mergeTypedUploadExtra(box?.extra)
                ),
                drugName: medicineName,
                dosePerTime: dosePerTime,
                doseValue: draft.doseValue?.nilIfBlank,
                doseUnit: doseUnit,
                frequencyType: frequencyType,
                everyNDays: draft.everyNDays.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) },
                weeklyWeekdays: draft.weeklyWeekdays ?? [],
                frequencyText: draft.frequencyText?.nilIfBlank ?? draft.frequencyCode?.nilIfBlank ?? "按医嘱",
                reminderTimes: draft.reminderTimes ?? [],
                startDate: startDate,
                endDate: draft.endDate?.nilIfBlank,
                instructions: draft.instructions?.nilIfBlank ?? "",
                reminderEnabled: draft.reminderEnabled ?? false,
                status: draft.status?.nilIfBlank ?? "active",
                extra: mergeTypedUploadExtra((draft.extra ?? [:]).merging(["sort_order": "\(index)"]) { current, _ in current })
            )
        }
    }

    func normalizedFrequencyType(_ raw: String?) -> String {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "every_n_days", "interval", "间隔":
            return "every_n_days"
        case "weekly", "week", "每周":
            return "weekly"
        default:
            return "daily"
        }
    }
}

private struct MedicineBoxCreatePayload: Encodable {
    let member: Int
    let medicineName: String
    let medicineType: String?
    let brandName: String
    let dosageForm: String
    let strength: String
    let doseUnit: String
    let totalQuantity: Double?
    let expireDate: String?
    let notes: String
    let extra: [String: String]

    enum CodingKeys: String, CodingKey {
        case member
        case medicineName = "medicine_name"
        case medicineType = "medicine_type"
        case brandName = "brand_name"
        case dosageForm = "dosage_form"
        case strength
        case doseUnit = "dose_unit"
        case totalQuantity = "total_quantity"
        case expireDate = "expire_date"
        case notes
        case extra
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
    /// 将草稿中的病情摘要与诊断合并为后端 `diagnosis_summary`。
    func mergedCaseDiagnosisSummary(draft: CaseRecognitionDraft) -> String {
        let summary = (draft.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let diagnosis = draft.diagnosis?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (summary.isEmpty, diagnosis.isEmpty) {
        case (true, true): return ""
        case (false, true): return summary
        case (true, false): return diagnosis
        case (false, false): return "\(summary)\n\n\(diagnosis)"
        }
    }

    /// 病例保存 `extra`：来源标记 + 就诊日期（主档无独立列时透传）。
    func caseDocumentExtra(draft: CaseRecognitionDraft) -> [String: String] {
        var extra = ["source": "typed_upload"]
        if let occurred = draft.occurredAt?.trimmingCharacters(in: .whitespacesAndNewlines),
           occurred.isEmpty == false {
            extra["occurred_at"] = occurred
        }
        return extra
    }

    func mergeTypedUploadExtra(_ draftExtra: [String: String]?) -> [String: String] {
        var merged: [String: String] = [:]
        if let draftExtra {
            for (k, v) in draftExtra { merged[k] = v }
        }
        merged["source"] = "typed_upload"
        return merged
    }

    // MARK: 构建体检报告保存参数
    func buildHealthExamPayload(
        memberID: Int,
        draft: HealthExamRecognitionDraft,
        rawOCRText: String,
        now: Date,
        fileIds: [Int]
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
            source: 2,                           // 来源：2=OCR（与后端 HealthExamReport.Source）
            rawOCR: ["text": rawOCRText],        // 原始OCR文本
            status: 1,                           // 状态：1=draft
            extra: ["source": "typed_upload"],
            details: buildHealthExamDetails(draft: draft, defaultDate: examDate.toISO8601()), // 体检明细项
            fileIds: fileIds
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
            // 排序：优先 item.sortOrder（字符串或数字文本），兜底用 index；解析为 0 时仍用 index
            let sortOrder: Int = {
                guard let s = item.sortOrder.parsedAsSortOrderInt() else { return index }
                return s == 0 ? index : s
            }()

            let defaultResultAt = Date.parseOrNow(defaultDate)
            let resultAt = Date.parseOrNow(item.resultAt, defaultDate: defaultResultAt).toISO8601()
            let payload = SparkMedicalWorkflowAPI.MedicalReportDetailPayload(
                category: item.category,
                subCategory: item.subCategory ?? "",
                itemName: item.itemName ?? "",
                itemCode: item.itemCode ?? "",
                resultValue: item.resultValue ?? "",
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

    // MARK: 构建医疗报告保存参数
    func buildMedicalReportPayloads(
        memberID: Int,
        drafts: [MedicalReportRecognitionDraft],
        sourceFileIds: [Int],
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
            // 报告分类
            let category = draft.category ?? "medical_report"
            // 报告内容（优先详情，兜底标题）
            let findingsText = draft.content.isEmpty ? draft.title : draft.content
            
            // 构建报告明细
            let detailRows: [SparkMedicalWorkflowAPI.MedicalReportDetailPayload] = draft.details.enumerated().map { index, row in
                let sortOrder: Int = {
                    guard let s = row.sortOrder.parsedAsSortOrderInt() else { return index }
                    return s == 0 ? index : s
                }()

                let defaultResultAt = Date.parseOrNow(dateText)
                let resultAt = Date.parseOrNow(row.resultAt, defaultDate: defaultResultAt).toISO8601()
                let payload = SparkMedicalWorkflowAPI.MedicalReportDetailPayload(
                    category: row.category,
                    subCategory: row.subCategory ?? "",
                    itemName: row.itemName ?? "",
                    itemCode: row.itemCode ?? "",
                    resultValue: row.resultValue ?? "",
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
                category: category,
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
                fileIds: sourceFileIds,
                details: detailRows
            )
        }
    }

    // MARK: - 组合创建辅助方法（使用 CombinedMedicalCreateAPI）

    /// 使用组合创建 API 保存病例文档（汇总草稿：主档 + 可选症状/就诊/手术/随访/检查/处方批次）
    func saveCombinedCase(
        memberID: Int,
        draft: CaseRecognitionDraft,
        envelope: MedicalDocumentRecognitionEnvelope,
        now: Date
    ) async throws -> MedicalDocumentSaveReceipt {
        let sourceFileIds = extractSourceFileIds(from: envelope)
        let diagnosisText = mergedCaseDiagnosisSummary(draft: draft)
        let medicalCase = MedicalCaseCreateRequest(
            title: draft.title,
            hospitalName: draft.hospitalName,
            diagnosisSummary: diagnosisText.isEmpty ? nil : diagnosisText,
            ageAtVisit: draft.ageAtVisit.parsedAsAgeAtVisitInteger(),
            extra: caseDocumentExtra(draft: draft)
        )
        // 后端组合接口：症状/就诊/手术/随访各单条；检查报告可多选。
        let symptomRequest = draft.symptom?.toCreateRequest()
        let visitRequest = draft.visit?.toCreateRequest()
        let surgeryRequest = draft.surgery?.toCreateRequest()
        let followUpRequest = draft.followUps?.first.map { $0.toCreateRequest() }
        let examReports = draft.examinationReports?.map { $0.toExaminationReportCreateRequest() }

        let request = CombinedMedicalCreateRequest(
            member: MemberCreateRequestWithId(
                id: memberID,
                name: nil,
                gender: nil,
                birthDate: nil,
                relationship: nil,
                extra: nil
            ),
            medicalCase: medicalCase,
            symptom: symptomRequest,
            visit: visitRequest,
            surgery: surgeryRequest,
            followUp: followUpRequest,
            examinationReports: examReports,
            sourceFileIds: sourceFileIds
        )

        let response = try await combinedAPI.createCombinedMedical(request)
        logger.info(
            "病例文档组合创建成功，memberID=\(response.memberId), caseID=\(response.medicalCaseId), exams=\(response.examinationReportIds?.count ?? 0)",
            module: .medical
        )
        return MedicalDocumentSaveReceipt(
            recordID: response.medicalCaseId,
            savedAt: now,
            isSuccess: true
        )
    }

    /// 使用体检专用工作流保存（`POST /api/v1/medical/workflows/health-exams/save/`），不创建病历组合包。
    func saveHealthExamReport(
        memberID: Int,
        draft: HealthExamRecognitionDraft,
        envelope: MedicalDocumentRecognitionEnvelope,
        now: Date
    ) async throws -> MedicalDocumentSaveReceipt {
        let fileIds = extractSourceFileIds(from: envelope)
        let payload = buildHealthExamPayload(
            memberID: memberID,
            draft: draft,
            rawOCRText: envelope.rawOCRText,
            now: now,
            fileIds: fileIds
        )
        let reportId = try await workflowAPI.saveHealthExam(payload)
        logger.info(
            "体检报告工作流保存成功，memberID=\(memberID), healthExamReportID=\(reportId)",
            module: .medical
        )
        return MedicalDocumentSaveReceipt(
            recordID: reportId,
            savedAt: now,
            isSuccess: true
        )
    }

    /// 使用独立新增 API 保存医疗检查报告（不创建病例）
    func saveStandaloneMedicalReports(
        memberID: Int,
        drafts: [MedicalReportRecognitionDraft],
        envelope: MedicalDocumentRecognitionEnvelope,
        now: Date
    ) async throws -> MedicalDocumentSaveReceipt {
        let sourceFileIds = extractSourceFileIds(from: envelope)
        let payloads = try buildMedicalReportPayloads(
            memberID: memberID,
            drafts: drafts,
            sourceFileIds: sourceFileIds,
            now: now
        )

        var lastReportID: Int?
        for payload in payloads {
            let reportID = try await workflowAPI.createMedicalReport(payload)
            lastReportID = reportID
        }

        guard let recordID = lastReportID else {
            throw NSError(
                domain: "DefaultTypedMedicalDocumentSaver",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "medical report drafts is empty"]
            )
        }
        logger.info(
            "医疗检查报告独立创建成功，memberID=\(memberID), reportCount=\(payloads.count), lastReportID=\(recordID)",
            module: .medical
        )
        return MedicalDocumentSaveReceipt(
            recordID: recordID,
            savedAt: now,
            isSuccess: true
        )
    }

    /// 从信封中提取源文件 ID
    func extractSourceFileIds(from envelope: MedicalDocumentRecognitionEnvelope) -> [Int] {
        // 这里假设 MedicalUploadLocalFile 有 remoteFileId 属性
        // 实际实现需要根据真实的数据结构调整
        return []
    }

}
