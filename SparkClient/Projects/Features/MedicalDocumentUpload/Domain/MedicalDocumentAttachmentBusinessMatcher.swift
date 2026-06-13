import Foundation

/// 医疗文档附件业务匹配器。

/// 医疗文档附件业务匹配器
/// 核心职责：根据OCR文本，将上传的医疗文件自动匹配关联到对应医疗文档节点（病历/报告/处方等）
enum MedicalDocumentAttachmentBusinessMatcher {
    
    /// 对外暴露的主匹配入口：匹配文件并更新提取结果
    /// - Parameters:
    ///   - files: 待匹配的本地上传文件列表
    ///   - output: 原始文档提取输出结果
    /// - Returns: 完成附件匹配后的新提取结果
    static func matchAndUpdate(
        files: [MedicalUploadLocalFile],
        output: MedicalDocumentTypedExtractionOutput
    ) -> MedicalDocumentTypedExtractionOutput {
        // 执行核心匹配逻辑，更新结构化结果
        let typedResult = matchAndUpdate(files: files, typedResult: output.typedResult)
        // 组装新的输出结果（仅替换匹配后的结构化数据，其余元数据保持不变）
        return MedicalDocumentTypedExtractionOutput(
            envelope: MedicalDocumentRecognitionEnvelope(
                memberID: output.envelope.memberID,
                sourceFiles: files,
                rawOCRText: output.envelope.rawOCRText,
                typeResolution: output.envelope.typeResolution
            ),
            typedResult: typedResult,
            extractedJSON: output.extractedJSON,
            payloadPreview: output.payloadPreview
        )
    }

    /// 内部核心匹配方法：根据文档类型分发匹配逻辑
    /// - Parameters:
    ///   - files: 上传文件
    ///   - typedResult: 结构化识别结果
    /// - Returns: 完成附件绑定的新结构化结果
    private static func matchAndUpdate(
        files: [MedicalUploadLocalFile],
        typedResult: MedicalDocumentTypedResult
    ) -> MedicalDocumentTypedResult {
        switch typedResult {
            // 病历文档：按优先级匹配→兜底→根节点挂载
        case .caseDocument(var draft):
            for file in files {
                // 跳过无OCR文本的文件
                guard let ocrText = file.ocrText, !ocrText.isEmpty else { continue }

                // 检测文档类型与置信度
                let (detectedMode, confidence) = DocumentTypeDetector.detect(text: ocrText)
                var matched = false

                // 高置信度：按文档类型精准匹配
                if confidence >= 35, let detectedMode {
                    matched = matchByDocumentType(
                        mode: detectedMode,
                        ocrText: ocrText,
                        draft: &draft,
                        fileID: file.id
                    )
                }

                // 未匹配：使用原有兜底匹配逻辑
                if !matched {
                    matched = matchByOriginalLogic(
                        ocrText: ocrText,
                        draft: &draft,
                        fileID: file.id
                    )
                }

                // 仍未匹配：直接挂载到病历根节点
                if !matched {
                    draft.appendAttachmentFileID(file.id, to: .caseRoot)
                }
            }
            return .caseDocument(draft)

            // 体检报告：所有附件直接绑定
        case .healthExamReport(var draft):
            for file in files {
                guard let ocrText = file.ocrText, !ocrText.isEmpty else { continue }
                draft.attachmentFileIds = draft.attachmentFileIds.appendingUnique(file.id)
            }
            return .healthExamReport(draft)

            // 医学检查报告：执行报告专用匹配
        case .medicalReport(var drafts):
            matchReports(files: files, reports: &drafts)
            return .medicalReport(drafts)

            // 处方单：执行处方匹配（支持多处方数组）
        case .prescription(var drafts):
            matchPrescriptions(files: files, prescriptions: &drafts)
            return .prescription(drafts)

            // 用药计划：执行用药匹配
        case .medicationPlan(var drafts):
            matchMedications(files: files, medications: &drafts)
            return .medicationPlan(drafts)

            // 药盒：执行药盒匹配
        case .medicineBoxes(var drafts):
            matchMedicineBoxes(files: files, boxes: &drafts)
            return .medicineBoxes(drafts)
        }
    }

    /// 基于文档类型精准匹配（高置信度优先策略）
    /// 匹配顺序与HealthClient保持一致：
    /// - 检查报告 → 病历文档(就诊→症状→根节点) → 用药(处方→用药计划)
    private static func matchByDocumentType(
        mode: UploadMode,
        ocrText: String,
        draft: inout CaseRecognitionDraft,
        fileID: UUID
    ) -> Bool {
        switch mode {
            // 检查/检验报告：遍历报告列表匹配
        case .checkupReport, .examReport:
            if let reports = draft.examinationReports {
                for index in reports.indices where matchText(ocrText, with: reports[index]) {
                    draft.appendAttachmentFileID(fileID, to: .examinationReport(index))
                    return true
                }
            }

            // 病历文档：按就诊信息→症状→病历根节点顺序匹配
        case .caseDocument:
            if let visit = draft.visit, matchText(ocrText, with: visit) {
                draft.appendAttachmentFileID(fileID, to: .visit)
                return true
            }

            if let symptom = draft.symptom, matchText(ocrText, with: symptom) {
                draft.appendAttachmentFileID(fileID, to: .symptom)
                return true
            }

            if matchText(ocrText, with: draft) {
                draft.appendAttachmentFileID(fileID, to: .caseRoot)
                return true
            }

            // 用药：按处方批次→用药计划顺序匹配
        case .medication:
            if let prescriptions = draft.prescriptions {
                for index in prescriptions.indices where matchText(ocrText, with: prescriptions[index]) {
                    draft.appendAttachmentFileID(fileID, to: .prescription(index))
                    return true
                }

                // 匹配用药计划子项
                for batchIndex in prescriptions.indices {
                    let plans = prescriptions[batchIndex].medicationPlans ?? []
                    for planIndex in plans.indices where matchText(ocrText, with: plans[planIndex]) {
                        draft.prescriptions?[safe: batchIndex]?.medicationPlans?[safe: planIndex]?.appendAttachmentFileID(fileID)
                        return true
                    }
                }
            }
        }

        return false
    }

    /// 原有兜底匹配逻辑（无类型检测/低置信度时使用）
    /// 匹配顺序：检查报告→症状→就诊→处方→用药→手术→随访→病历根节点
    private static func matchByOriginalLogic(
        ocrText: String,
        draft: inout CaseRecognitionDraft,
        fileID: UUID
    ) -> Bool {
        // 匹配检查报告
        if let reports = draft.examinationReports {
            for index in reports.indices where matchText(ocrText, with: reports[index]) {
                draft.appendAttachmentFileID(fileID, to: .examinationReport(index))
                return true
            }
        }

        // 匹配症状
        if let symptom = draft.symptom, matchText(ocrText, with: symptom) {
            draft.appendAttachmentFileID(fileID, to: .symptom)
            return true
        }

        // 匹配就诊信息
        if let visit = draft.visit, matchText(ocrText, with: visit) {
            draft.appendAttachmentFileID(fileID, to: .visit)
            return true
        }

        // 匹配处方与用药计划
        if let prescriptions = draft.prescriptions {
            for index in prescriptions.indices where matchText(ocrText, with: prescriptions[index]) {
                draft.appendAttachmentFileID(fileID, to: .prescription(index))
                return true
            }

            for batchIndex in prescriptions.indices {
                let plans = prescriptions[batchIndex].medicationPlans ?? []
                for planIndex in plans.indices where matchText(ocrText, with: plans[planIndex]) {
                    draft.prescriptions?[safe: batchIndex]?.medicationPlans?[safe: planIndex]?.appendAttachmentFileID(fileID)
                    return true
                }
            }
        }

        // 匹配手术信息
        if let surgery = draft.surgery, matchText(ocrText, with: surgery) {
            draft.appendAttachmentFileID(fileID, to: .surgery)
            return true
        }

        // 匹配随访信息
        if let followUps = draft.followUps {
            for index in followUps.indices where matchText(ocrText, with: followUps[index]) {
                draft.appendAttachmentFileID(fileID, to: .followUp(index))
                return true
            }
        }

        // 最终兜底：匹配病历根节点
        if matchText(ocrText, with: draft) {
            draft.appendAttachmentFileID(fileID, to: .caseRoot)
            return true
        }

        return false
    }

    /// 医学检查报告专用匹配逻辑
    private static func matchReports(files: [MedicalUploadLocalFile], reports: inout [MedicalReportRecognitionDraft]) {
        for file in files {
            guard let ocrText = file.ocrText, !ocrText.isEmpty else { continue }
            let (detectedMode, confidence) = DocumentTypeDetector.detect(text: ocrText)
            var matched = false

            // 高置信度检查报告类型：优先匹配
            if confidence >= 35, detectedMode == .checkupReport || detectedMode == .examReport {
                matched = bindFirstMatchingReport(ocrText: ocrText, fileID: file.id, reports: &reports)
            }

            // 兜底匹配
            if !matched {
                matched = bindFirstMatchingReport(ocrText: ocrText, fileID: file.id, reports: &reports)
            }

            // 无匹配时绑定到第一个报告
            if !matched, !reports.isEmpty {
                reports[reports.startIndex].appendAttachmentFileID(file.id)
            }
        }
    }

    /// 多处方专用匹配逻辑
    private static func matchPrescriptions(
        files: [MedicalUploadLocalFile],
        prescriptions: inout [PrescriptionRecognitionDraft]
    ) {
        guard prescriptions.isEmpty == false else { return }
        for file in files {
            guard let ocrText = file.ocrText, !ocrText.isEmpty else { continue }
            let (detectedMode, confidence) = DocumentTypeDetector.detect(text: ocrText)
            var matched = false

            if confidence >= 35, detectedMode == .medication {
                for index in prescriptions.indices where matchText(ocrText, with: prescriptions[index]) {
                    prescriptions[index].appendAttachmentFileID(file.id)
                    matched = true
                    break
                }
            }

            if matched == false {
                for index in prescriptions.indices {
                    if bindPrescriptionOrMedication(
                        ocrText: ocrText,
                        fileID: file.id,
                        prescription: &prescriptions[index]
                    ) {
                        matched = true
                        break
                    }
                }
            }

            if matched == false {
                prescriptions[prescriptions.startIndex].appendAttachmentFileID(file.id)
            }
        }
    }

    /// 处方单专用匹配逻辑
    private static func matchPrescription(files: [MedicalUploadLocalFile], prescription: inout PrescriptionRecognitionDraft) {
        for file in files {
            guard let ocrText = file.ocrText, !ocrText.isEmpty else { continue }
            let (detectedMode, confidence) = DocumentTypeDetector.detect(text: ocrText)
            var matched = false

            // 高置信度用药类型：优先匹配
            if confidence >= 35, detectedMode == .medication {
                matched = bindPrescriptionOrMedication(ocrText: ocrText, fileID: file.id, prescription: &prescription)
            }

            // 兜底匹配
            if !matched {
                matched = bindPrescriptionOrMedication(ocrText: ocrText, fileID: file.id, prescription: &prescription)
            }

            // 无匹配直接绑定到处方
            if !matched {
                prescription.appendAttachmentFileID(file.id)
            }
        }
    }

    /// 用药计划专用匹配逻辑
    private static func matchMedications(files: [MedicalUploadLocalFile], medications: inout [MedicationPlanRecognitionDraft]) {
        for file in files {
            guard let ocrText = file.ocrText, !ocrText.isEmpty else { continue }
            let (detectedMode, confidence) = DocumentTypeDetector.detect(text: ocrText)
            var matched = false

            // 高置信度用药类型匹配
            if confidence >= 35, detectedMode == .medication {
                matched = bindFirstMatchingMedication(ocrText: ocrText, fileID: file.id, medications: &medications)
            }

            // 兜底匹配
            if !matched {
                matched = bindFirstMatchingMedication(ocrText: ocrText, fileID: file.id, medications: &medications)
            }

            // 无匹配绑定到第一个用药计划
            if !matched, !medications.isEmpty {
                medications[medications.startIndex].appendAttachmentFileID(file.id)
            }
        }
    }

    /// 药盒匹配逻辑
    private static func matchMedicineBoxes(files: [MedicalUploadLocalFile], boxes: inout [MedicineBoxRecognitionDraft]) {
        guard boxes.isEmpty == false else { return }

        for file in files {
            if let ocrText = file.ocrText, ocrText.isEmpty == false {
                var matched = false
                for index in boxes.indices where matchText(ocrText, with: boxes[index]) {
                    boxes[index].appendAttachmentFileID(file.id)
                    matched = true
                    break
                }
                if matched == false {
                    boxes[boxes.startIndex].appendAttachmentFileID(file.id)
                }
            } else {
                boxes[boxes.startIndex].appendAttachmentFileID(file.id)
            }
        }
    }

    /// 绑定第一个匹配的检查报告
    private static func bindFirstMatchingReport(
        ocrText: String,
        fileID: UUID,
        reports: inout [MedicalReportRecognitionDraft]
    ) -> Bool {
        for index in reports.indices where matchText(ocrText, with: reports[index]) {
            reports[index].appendAttachmentFileID(fileID)
            return true
        }
        return false
    }

    /// 绑定处方或用药计划
    private static func bindPrescriptionOrMedication(
        ocrText: String,
        fileID: UUID,
        prescription: inout PrescriptionRecognitionDraft
    ) -> Bool {
        // 优先匹配处方本身
        if matchText(ocrText, with: prescription) {
            prescription.appendAttachmentFileID(fileID)
            return true
        }

        // 匹配用药计划子项
        guard var plans = prescription.medicationPlans else { return false }
        for index in plans.indices where matchText(ocrText, with: plans[index]) {
            plans[index].appendAttachmentFileID(fileID)
            prescription.medicationPlans = plans
            return true
        }
        return false
    }

    /// 绑定第一个匹配的用药计划
    private static func bindFirstMatchingMedication(
        ocrText: String,
        fileID: UUID,
        medications: inout [MedicationPlanRecognitionDraft]
    ) -> Bool {
        for index in medications.indices where matchText(ocrText, with: medications[index]) {
            medications[index].appendAttachmentFileID(fileID)
            return true
        }
        return false
    }

    // MARK: - 文本匹配评分算法
    // 规则：对OCR文本与文档字段做归一化匹配，按权重累加得分，达到阈值则判定匹配成功

    /// 病历文档文本匹配：标题/诊断/摘要/医院/症状/用药 加权评分
    private static func matchText(_ ocrText: String, with draft: CaseRecognitionDraft) -> Bool {
        let text = normalized(ocrText)
        var score = 0

        if contains(text, draft.title) { score += 3 }
        if contains(text, draft.diagnosis) { score += 3 }
        if contains(text, draft.summary) { score += 2 }
        if contains(text, draft.hospitalName) { score += 1 }
        if let symptom = draft.symptom, contains(text, symptom.name) { score += 2 }
        for batch in draft.prescriptions ?? [] {
            for medication in batch.medicationPlans ?? [] where contains(text, medication.displayMedicineName) {
                score += 2
            }
        }

        // 总分≥3判定匹配
        return score >= 3
    }

    /// 检查报告文本匹配：标题/分类/内容/医院/检查项 加权评分
    private static func matchText(_ ocrText: String, with draft: MedicalReportRecognitionDraft) -> Bool {
        let text = normalized(ocrText)
        var score = 0

        if contains(text, draft.title) { score += 3 }
        if contains(text, draft.category) { score += 2 }
        if contains(text, draft.content) { score += 2 }
        if contains(text, draft.hospital) { score += 1 }

        // 检查明细项加权
        var detailScore = 0
        for item in draft.details {
            if contains(text, item.itemName) { detailScore += 3 }
            if contains(text, item.resultValue) { detailScore += 1 }
            if contains(text, item.referenceRange) { detailScore += 1 }
            if contains(text, item.modality) { detailScore += 2 }
            if contains(text, item.bodyPart) { detailScore += 3 }
            if contains(text, item.diagnosis) { detailScore += 2 }
        }
        score += detailScore

        // 动态阈值：有明细项阈值≥5，否则≥2
        var threshold = 2
        if !draft.details.isEmpty {
            threshold = max(threshold, 5)
        }
        return score >= threshold
    }

    /// 症状匹配：名称/严重程度/部位/备注 评分≥2
    private static func matchText(_ ocrText: String, with draft: SymptomRecognitionDraft) -> Bool {
        let text = normalized(ocrText)
        var score = 0
        if contains(text, draft.name) { score += 3 }
        if contains(text, draft.severity) { score += 1 }
        if contains(text, draft.bodyPart) { score += 1 }
        if contains(text, draft.notes) { score += 1 }
        return score >= 2
    }

    /// 就诊信息匹配：科室/医生/就诊号/备注 评分≥3
    private static func matchText(_ ocrText: String, with draft: VisitRecognitionDraft) -> Bool {
        let text = normalized(ocrText)
        var score = 0
        if contains(text, draft.department) { score += 2 }
        if contains(text, draft.doctorName) { score += 1 }
        if contains(text, draft.visitNo) { score += 2 }
        if contains(text, draft.notes) { score += 2 }
        return score >= 3
    }

    /// 用药计划匹配：药名/剂量/频次 评分≥3
    private static func matchText(_ ocrText: String, with draft: MedicationPlanRecognitionDraft) -> Bool {
        let text = normalized(ocrText)
        var score = 0
        if contains(text, draft.displayMedicineName) { score += 3 }
        if contains(text, draft.dosePerTime) || contains(text, draft.doseValue) { score += 2 }
        if contains(text, draft.frequencyText) || contains(text, draft.frequencyType) { score += 1 }
        return score >= 3
    }

    /// 药盒匹配：药名/规格/剂型 评分≥3
    private static func matchText(_ ocrText: String, with draft: MedicineBoxRecognitionDraft) -> Bool {
        let text = normalized(ocrText)
        var score = 0
        if contains(text, draft.displayMedicineName) { score += 3 }
        if contains(text, draft.strength) { score += 2 }
        if contains(text, draft.dosageForm) { score += 1 }
        return score >= 3
    }

    /// 手术信息匹配：手术名/医生/部位 评分≥2
    private static func matchText(_ ocrText: String, with draft: SurgeryRecognitionDraft) -> Bool {
        let text = normalized(ocrText)
        var score = 0
        if contains(text, draft.procedureName) { score += 3 }
        if contains(text, draft.surgeon) { score += 1 }
        if contains(text, draft.site) { score += 1 }
        return score >= 2
    }

    /// 随访信息匹配：结果/下次行动/方式 评分≥2
    private static func matchText(_ ocrText: String, with draft: FollowUpRecognitionDraft) -> Bool {
        let text = normalized(ocrText)
        var score = 0
        if contains(text, draft.outcome) { score += 3 }
        if contains(text, draft.nextAction) { score += 2 }
        if contains(text, draft.method) { score += 1 }
        return score >= 2
    }

    /// 处方单匹配：处方号/机构/开方医生/诊断/药品 评分≥4
    private static func matchText(_ ocrText: String, with draft: PrescriptionRecognitionDraft) -> Bool {
        let text = normalized(ocrText)
        var score = 0

        if contains(text, draft.prescriptionNo) { score += 4 }
        if contains(text, draft.institutionName) { score += 3 }
        if contains(text, draft.prescriberName) { score += 2 }
        if contains(text, draft.diagnosis) { score += 2 }
        for medication in draft.medicationPlans ?? [] where contains(text, medication.displayMedicineName) {
            score += 1
        }

        return score >= 4
    }

    /// 包含判断工具方法：空值过滤+长度校验+归一化匹配
    private static func contains(_ normalizedText: String, _ raw: String?) -> Bool {
        guard let value = raw?.nilIfBlank else { return false }
        let normalizedValue = normalized(value)
        // 关键词长度≥2才参与匹配，避免误判
        guard normalizedValue.count >= 2 else { return false }
        return normalizedText.contains(normalizedValue)
    }

    /// 文本归一化：转小写 + 去除空格/换行符
    nonisolated private static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && !$0.isNewline }
    }
}

private enum UploadMode {
    case checkupReport
    case examReport
    case caseDocument
    case medication
}

private enum DocumentTypeDetector {
    static func detect(text: String) -> (mode: UploadMode?, confidence: Int) {
        let text = text.lowercased()
        let candidates: [(UploadMode, Int)] = [
            (.checkupReport, score(text, high: ["体检报告", "健康体检", "体检中心", "体检结论", "体检建议"], medium: ["参考范围", "正常范围", "总胆固醇", "血红蛋白"])),
            (.caseDocument, score(text, high: ["门诊病历", "住院病历", "急诊病历", "主诉", "现病史", "既往史", "初步诊断"], medium: ["辅助检查", "过敏史", "住院号", "门诊号"])),
            (.examReport, score(text, high: ["诊断报告单", "检查报告单", "影像表现", "诊断意见", "影像诊断", "检验报告单"], medium: ["检查项目", "检测项目", "报告医生", "标本类型", "参考区间"])),
            (.medication, score(text, high: ["处方笺", "处方单", "处方", "rp", "用法", "用量"], medium: ["药品名称", "发药清单", "医师签名", "tid", "bid", "qd"]))
        ]
        guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 > 0 else {
            return (nil, 0)
        }
        return (best.0, min(best.1, 100))
    }

    private static func score(_ text: String, high: [String], medium: [String]) -> Int {
        var score = 0
        for keyword in high where text.contains(keyword.lowercased()) {
            score += 15
        }
        score += min(medium.filter { text.contains($0.lowercased()) }.count, 5) * 2
        return score
    }
}

private enum CaseCandidate {
    case caseRoot
    case symptom
    case visit
    case surgery
    case followUp(Int)
    case prescription(Int)
    case examinationReport(Int)
}

private extension CaseRecognitionDraft {
    mutating func appendAttachmentFileID(_ fileID: UUID, to candidate: CaseCandidate) {
        switch candidate {
        case .caseRoot:
            attachmentFileIds = attachmentFileIds.appendingUnique(fileID)
        case .symptom:
            symptom?.appendAttachmentFileID(fileID)
        case .visit:
            visit?.appendAttachmentFileID(fileID)
        case .surgery:
            surgery?.appendAttachmentFileID(fileID)
        case .followUp(let index):
            followUps?[safe: index]?.appendAttachmentFileID(fileID)
        case .prescription(let index):
            prescriptions?[safe: index]?.appendAttachmentFileID(fileID)
        case .examinationReport(let index):
            examinationReports?[safe: index]?.appendAttachmentFileID(fileID)
        }
    }
}

private extension SymptomRecognitionDraft {
    mutating func appendAttachmentFileID(_ fileID: UUID) {
        attachmentFileIds = attachmentFileIds.appendingUnique(fileID)
    }
}

private extension VisitRecognitionDraft {
    mutating func appendAttachmentFileID(_ fileID: UUID) {
        attachmentFileIds = attachmentFileIds.appendingUnique(fileID)
    }
}

private extension SurgeryRecognitionDraft {
    mutating func appendAttachmentFileID(_ fileID: UUID) {
        attachmentFileIds = attachmentFileIds.appendingUnique(fileID)
    }
}

private extension FollowUpRecognitionDraft {
    mutating func appendAttachmentFileID(_ fileID: UUID) {
        attachmentFileIds = attachmentFileIds.appendingUnique(fileID)
    }
}

private extension PrescriptionRecognitionDraft {
    mutating func appendAttachmentFileID(_ fileID: UUID) {
        attachmentFileIds = attachmentFileIds.appendingUnique(fileID)
    }
}

private extension MedicalReportRecognitionDraft {
    mutating func appendAttachmentFileID(_ fileID: UUID) {
        attachmentFileIds = attachmentFileIds.appendingUnique(fileID)
    }
}

private extension MedicationPlanRecognitionDraft {
    var displayMedicineName: String? {
        medicineName?.nilIfBlank ?? medicineBox?.medicineName?.nilIfBlank ?? brandName?.nilIfBlank
    }

    mutating func appendAttachmentFileID(_ fileID: UUID) {
        attachmentFileIds = attachmentFileIds.appendingUnique(fileID)
    }
}

private extension MedicineBoxRecognitionDraft {
    var displayMedicineName: String? {
        medicineName?.nilIfBlank ?? brandName?.nilIfBlank
    }

    mutating func appendAttachmentFileID(_ fileID: UUID) {
        attachmentFileIds = attachmentFileIds.appendingUnique(fileID)
    }
}

private extension Array where Element: Equatable {
    func appendingUnique(_ value: Element) -> [Element] {
        contains(value) ? self : self + [value]
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        get {
            indices.contains(index) ? self[index] : nil
        }
        set {
            guard indices.contains(index), let newValue else { return }
            self[index] = newValue
        }
    }
}
