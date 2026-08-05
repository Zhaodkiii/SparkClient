import Foundation

// MARK: - 本地医疗文档分类引擎（统一模块）

private struct LocalMedicalDocumentClassifier {
    private struct WeightedFeature {
        let terms: [String]
        let weight: Int

        init(_ terms: [String], weight: Int) {
            self.terms = terms
            self.weight = weight
        }
    }

    struct MatchResult {
        let kind: MedicalDocumentKind
        let isMatch: Bool
        let confidence: Int
    }

    static func classify(text: String) -> [MatchResult] {
        let input = text.lowercased()

        let caseResult = CaseDocument.detect(text: input)
        let prescriptionResult = Prescription.detect(text: input)
        let healthExamResult = HealthExam.detect(text: input)
        let medicalReportResult = MedicalReport.detect(text: input)
        let medicationPlanResult = MedicationPlan.detect(text: input)
        let medicineBoxResult = MedicineBox.detect(text: input)

        return [
            MatchResult(kind: .caseDocument, isMatch: caseResult.isMatch, confidence: caseResult.confidence),
            MatchResult(kind: .prescription, isMatch: prescriptionResult.isMatch, confidence: prescriptionResult.confidence),
            MatchResult(kind: .healthExamReport, isMatch: healthExamResult.isMatch, confidence: healthExamResult.confidence),
            MatchResult(kind: .medicalReport, isMatch: medicalReportResult.isMatch, confidence: medicalReportResult.confidence),
            MatchResult(kind: .medicationPlan, isMatch: medicationPlanResult.isMatch, confidence: medicationPlanResult.confidence),
            MatchResult(kind: .medicineBox, isMatch: medicineBoxResult.isMatch, confidence: medicineBoxResult.confidence)
        ]
    }

    // MARK: - 内部协议定义
    private protocol Detector {
        static var weightedFeatures: [WeightedFeature] { get }
        static var threshold: Int { get }
        static func detect(text: String) -> (isMatch: Bool, confidence: Int)
        static func additionalScoring(on text: String) -> Int
    }

    private static func baseDetect<D: Detector>(
        text: String,
        detectorType: D.Type
    ) -> (isMatch: Bool, confidence: Int) {
        var score = 0

        // A. 显式权重特征：标题/结构性字段权重大，普通医学词权重小，避免靠词数硬凑。
        for feature in detectorType.weightedFeatures {
            let matchedCount = feature.terms.filter { text.contains($0.lowercased()) }.count
            guard matchedCount > 0 else { continue }
            score += min(matchedCount, 3) * feature.weight
        }

        // B. 结构化加分/互斥扣分
        score += detectorType.additionalScoring(on: text)

        let confidence = min(100, max(0, score))
        return (confidence >= detectorType.threshold, confidence)
    }

    // MARK: - 1) 检查/检验报告（重点优化检验化验单）
    private struct MedicalReport: Detector {
        static let threshold = 30

        static let weightedFeatures = [
            // 权重 18：报告标题和明确类型词，通常直接决定路由。
            WeightedFeature([
                "诊断报告单", "检查报告单", "检验报告单", "检验报告", "检测报告",
                "影像诊断", "病理诊断", "彩超检查", "radiology report", "diagnostic report",
                "imaging report", "ultrasound report", "ct report", "mri report",
                "pathology report", "laboratory report", "lab report", "test report"
            ], weight: 18),
            // 权重 10：影像/病理/检验报告的独有结构字段。
            WeightedFeature([
                "影像表现", "诊断意见", "检查所见", "超声描述", "超声提示",
                "镜下所见", "肉眼所见", "标本类型", "标本号", "条码号",
                "findings", "impression", "conclusion", "specimen type", "specimen id",
                "accession number", "clinical indication", "technique"
            ], weight: 10),
            // 权重 6：报告流程字段。
            WeightedFeature([
                "检查项目", "检测项目", "检查部位", "报告医生", "审核医生",
                "检验者", "申请医生", "送检医生", "临床检验",
                "exam", "procedure", "body part", "reported by", "verified by",
                "ordering physician", "referring physician", "collected", "resulted"
            ], weight: 6),
            // 权重 3：检查方式和异常发现词，单独出现不足以定类。
            WeightedFeature([
                "ct", "mri", "b超", "超声", "x-ray", "xray", "ultrasound", "radiograph",
                "回声", "结节", "肿块", "占位", "病灶", "nodule", "mass", "lesion",
                "opacity", "density", "calcification"
            ], weight: 3)
        ]

        static func detect(text: String) -> (isMatch: Bool, confidence: Int) {
            LocalMedicalDocumentClassifier.baseDetect(text: text, detectorType: Self.self)
        }

        static func additionalScoring(on text: String) -> Int {
            var extra = 0

            // 影像学结构
            if (text.contains("影像表现") || text.contains("检查所见")) && text.contains("诊断意见") {
                extra += 20
            }
            let systems = ["ti-rads", "bi-rads", "li-rads", "pi-rads", "lung-rads"]
            if systems.contains(where: { text.contains($0) }) { extra += 25 }

            // 实验室检验单结构（关键优化）
            if text.contains("结果") && text.contains("参考区间") && text.contains("单位") {
                extra += 25
            }
            if text.contains("result") && (text.contains("reference range") || text.contains("normal range")) && text.contains("unit") {
                extra += 25
            }
            if text.contains("检验互认项目") || text.contains("质评合格") {
                extra += 15
            }

            // 排除逻辑
            if text.contains("处方笺") || text.contains("处方单") || text.contains("prescription") || text.contains("rx") {
                if !text.contains("检查") && !text.contains("诊断") && !text.contains("report") { extra -= 15 }
            }
            if hasCaseHistoryStructure(text) { extra -= 20 }

            return extra
        }
    }

    // MARK: - 2) 病历
    private struct CaseDocument: Detector {
        static let threshold = 30
        static let weightedFeatures = [
            // 权重 18：病历/记录类标题。
            WeightedFeature([
                "门诊病历", "住院病历", "急诊病历", "入院记录", "出院记录", "出院小结",
                "病程记录", "medical record", "clinical record", "visit note",
                "progress note", "discharge summary", "admission note", "emergency record"
            ], weight: 18),
            // 权重 12：病史叙事结构，是病历最稳定的特征。
            WeightedFeature([
                "主诉", "现病史", "既往史", "个人史", "家族史", "体格检查",
                "chief complaint", "history of present illness", "hpi", "past medical history",
                "pmh", "review of systems", "physical examination", "family history"
            ], weight: 12),
            // 权重 8：诊疗过程字段。
            WeightedFeature([
                "初步诊断", "处理意见", "出院诊断", "入院诊断", "治疗经过", "出院医嘱",
                "assessment and plan", "assessment/plan", "plan", "hospital course",
                "discharge diagnosis", "admission diagnosis"
            ], weight: 8),
            // 权重 4：就诊身份与普通临床词。
            WeightedFeature([
                "辅助检查", "过敏史", "入院日期", "出院日期", "住院号", "医师签名", "门诊号",
                "症状", "体征", "随访", "医嘱", "复诊", "诊断", "治疗",
                "allergies", "mrn", "medical record number", "encounter", "follow-up",
                "symptom", "diagnosis", "treatment"
            ], weight: 4)
        ]

        static func detect(text: String) -> (isMatch: Bool, confidence: Int) {
            LocalMedicalDocumentClassifier.baseDetect(text: text, detectorType: Self.self)
        }

        static func additionalScoring(on text: String) -> Int {
            var extra = 0
            if text.contains("病历") && (text.contains("门诊") || text.contains("急诊")) { extra += 50 }
            if text.contains("medical record") && (text.contains("visit") || text.contains("encounter")) { extra += 30 }
            if hasCaseHistoryStructure(text) { extra += 20 }
            if text.contains("影像诊断") || text.contains("诊断意见") {
                if !text.contains("初步诊断") && !text.contains("处理意见") { extra -= 15 }
            }
            return extra
        }
    }

    // MARK: - 3) 处方
    private struct Prescription: Detector {
        static let threshold = 30
        static let weightedFeatures = [
            // 权重 18：处方标题/处方符号。
            WeightedFeature([
                "处方笺", "处方单", "门诊处方", "电子处方", "prescription", "prescription form",
                "rx", "℞", "e-prescription", "outpatient prescription"
            ], weight: 18),
            // 权重 12：处方流转和开具字段。
            WeightedFeature([
                "处方号", "处方编号", "开方日期", "发药清单", "审核", "调配", "发药",
                "医师签名", "药师签名", "prescription no", "rx number", "date prescribed",
                "dispense", "dispensed", "pharmacist", "prescriber", "refills"
            ], weight: 12),
            // 权重 8：用法剂量字段。
            WeightedFeature([
                "药品名称", "用法", "用量", "频次", "每次", "每日", "sig", "directions",
                "dosage", "dose", "route", "frequency", "take", "inject", "apply"
            ], weight: 8),
            // 权重 4：常见频次/单位，单独出现容易与药盒混淆。
            WeightedFeature([
                "tid", "bid", "qd", "qn", "qhs", "prn", "po", "iv", "ivgtt", "im",
                "片", "粒", "支", "瓶", "盒", "mg", "ml", "tablet", "capsule", "cap", "tab"
            ], weight: 4)
        ]

        static func detect(text: String) -> (isMatch: Bool, confidence: Int) {
            LocalMedicalDocumentClassifier.baseDetect(text: text, detectorType: Self.self)
        }

        static func additionalScoring(on text: String) -> Int {
            var extra = 0
            if (text.contains("处方") || text.contains("rp") || text.contains("rx") || text.contains("prescription"))
                && (text.contains("用法") || text.contains("sig") || text.contains("directions")) {
                extra += 20
            }
            if hasCaseHistoryStructure(text) { extra -= 20 }
            if text.contains("检查所见") || text.contains("影像诊断") {
                if !text.contains("处方") && !text.contains("用药") { extra -= 15 }
            }
            if hasMedicinePackageStructure(text) && !text.contains("处方") && !text.contains("prescription") {
                extra -= 20
            }
            return extra
        }
    }

    // MARK: - 4) 体检报告
    private struct HealthExam: Detector {
        static let threshold = 30
        static let weightedFeatures = [
            // 权重 18：体检/筛查类标题。
            WeightedFeature([
                "体检报告", "健康体检", "体检中心", "体检结论", "体检建议", "体检日期", "体检编号",
                "health examination report", "health check report", "annual physical",
                "executive health check", "wellness report", "preventive screening"
            ], weight: 18),
            // 权重 10：体检汇总结构。
            WeightedFeature([
                "总检结论", "总结建议", "体检套餐", "体检项目表", "一般检查", "内科检查", "外科检查",
                "summary recommendation", "health summary", "exam package", "screening package",
                "general examination", "physical examination"
            ], weight: 10),
            // 权重 5：大量指标型体检常见项目。
            WeightedFeature([
                "参考范围", "正常范围", "总胆固醇", "甘油三酯", "血红蛋白", "尿素氮",
                "身高", "体重", "血压", "bmi", "reference range", "normal range",
                "cholesterol", "triglycerides", "hemoglobin", "blood pressure", "body mass index"
            ], weight: 5),
            // 权重 3：体检建议/异常标记，普通报告也可能出现。
            WeightedFeature([
                "偏高", "偏低", "建议", "复查", "进一步检查", "定期体检",
                "high", "low", "abnormal", "follow up", "recheck", "recommendation"
            ], weight: 3)
        ]

        static func detect(text: String) -> (isMatch: Bool, confidence: Int) {
            LocalMedicalDocumentClassifier.baseDetect(text: text, detectorType: Self.self)
        }

        static func additionalScoring(on text: String) -> Int {
            var extra = 0
            if text.count > 5000 { extra += 10 } else if text.count > 2000 { extra += 5 }
            if text.contains("总结建议") && text.contains("体检中心") { extra += 20 }
            if text.contains("summary recommendation") && (text.contains("health check") || text.contains("physical exam")) { extra += 20 }
            if text.contains("健康体检") || text.contains("导读") { extra += 10 }
            if text.contains("health check") || text.contains("annual physical") { extra += 10 }
            if text.contains("主诉") || text.contains("现病史") || text.contains("chief complaint") { extra -= 20 }
            if text.contains("影像表现") && text.contains("诊断意见") { extra -= 15 }
            return extra
        }
    }

    // MARK: - 5) 用药计划
    private struct MedicationPlan: Detector {
        static let threshold = 32
        static let weightedFeatures = [
            // 权重 18：计划/方案标题，不等同于处方原件。
            WeightedFeature([
                "用药计划", "服药计划", "用药方案", "服药提醒", "药物治疗方案",
                "medication plan", "medicine schedule", "drug schedule", "medication schedule",
                "treatment plan", "medication regimen"
            ], weight: 18),
            // 权重 12：计划型时间字段。
            WeightedFeature([
                "开始日期", "结束日期", "长期服用", "提醒时间", "服药时间", "疗程",
                "start date", "end date", "duration", "course", "reminder time",
                "take at", "morning", "evening", "bedtime"
            ], weight: 12),
            // 权重 8：频次和剂量执行字段。
            WeightedFeature([
                "每日", "每周", "每隔", "饭前", "饭后", "睡前", "每次", "一次",
                "daily", "weekly", "every other day", "before meals", "after meals",
                "with food", "at bedtime", "once daily", "twice daily"
            ], weight: 8),
            // 权重 4：药品字段，需与时间/计划字段组合才可靠。
            WeightedFeature([
                "药品名称", "剂型", "规格", "剂量", "mg", "ml", "tablet", "capsule",
                "strength", "dose", "dosage form", "instructions"
            ], weight: 4)
        ]

        static func detect(text: String) -> (isMatch: Bool, confidence: Int) {
            LocalMedicalDocumentClassifier.baseDetect(text: text, detectorType: Self.self)
        }

        static func additionalScoring(on text: String) -> Int {
            var extra = 0
            if (text.contains("用药计划") || text.contains("medication plan") || text.contains("medication schedule"))
                && (text.contains("开始") || text.contains("start date") || text.contains("reminder")) {
                extra += 25
            }
            if (text.contains("reminder") || text.contains("提醒")) && (text.contains("daily") || text.contains("每日")) {
                extra += 15
            }
            if text.contains("处方笺") || text.contains("处方单") || text.contains("prescription no") || text.contains("rx number") {
                extra -= 18
            }
            if hasMedicinePackageStructure(text) { extra -= 15 }
            return extra
        }
    }

    // MARK: - 6) 药品/药盒包装
    private struct MedicineBox: Detector {
        static let threshold = 32
        static let weightedFeatures = [
            // 权重 18：包装和标签类标题。
            WeightedFeature([
                "药盒", "药品包装", "药瓶", "药品标签", "说明书", "外包装",
                "medicine box", "drug package", "medication package", "pill bottle",
                "package label", "drug label", "patient information leaflet"
            ], weight: 18),
            // 权重 12：监管/包装独有标识。
            WeightedFeature([
                "国药准字", "批准文号", "生产批号", "产品批号", "有效期至", "生产日期",
                "manufacturer", "lot number", "batch number", "expiry date", "expiration date",
                "exp.", "ndc", "rx only", "store at"
            ], weight: 12),
            // 权重 8：包装说明结构。
            WeightedFeature([
                "通用名称", "商品名称", "成份", "性状", "适应症", "禁忌", "不良反应",
                "generic name", "brand name", "active ingredient", "indications",
                "contraindications", "side effects", "warnings"
            ], weight: 8),
            // 权重 4：规格/数量/剂型，处方和计划也会出现。
            WeightedFeature([
                "规格", "剂型", "贮藏", "每盒", "片/盒", "粒/盒", "capsules", "tablets",
                "strength", "dosage form", "storage", "keep out of reach"
            ], weight: 4)
        ]

        static func detect(text: String) -> (isMatch: Bool, confidence: Int) {
            LocalMedicalDocumentClassifier.baseDetect(text: text, detectorType: Self.self)
        }

        static func additionalScoring(on text: String) -> Int {
            var extra = 0
            if hasMedicinePackageStructure(text) { extra += 25 }
            if (text.contains("国药准字") || text.contains("ndc")) && (text.contains("有效期") || text.contains("expiration")) {
                extra += 20
            }
            if text.contains("处方号") || text.contains("prescription no") || text.contains("rx number") {
                extra -= 25
            }
            if text.contains("开始日期") || text.contains("reminder time") || text.contains("服药提醒") {
                extra -= 18
            }
            return extra
        }
    }

    private static func hasCaseHistoryStructure(_ text: String) -> Bool {
        (text.contains("主诉") && text.contains("现病史"))
            || (text.contains("chief complaint") && text.contains("history of present illness"))
            || (text.contains("chief complaint") && text.contains("assessment and plan"))
    }

    private static func hasMedicinePackageStructure(_ text: String) -> Bool {
        (text.contains("批准文号") || text.contains("国药准字") || text.contains("生产批号") || text.contains("有效期至"))
            || (text.contains("lot number") || text.contains("batch number") || text.contains("ndc") || text.contains("expiration date"))
    }
}

/// 默认的医疗文档类型解析器
/// 遵循 MedicalDocumentTypeResolving 协议，实现文档类型自动识别功能
/// Sendable 标识：保证该类型可安全在多线程/异步环境中传递
struct DefaultMedicalDocumentTypeResolver: MedicalDocumentTypeResolving, Sendable {
    // MARK: - 依赖注入的核心服务
    /// AI运行时服务：负责调用大模型生成文本（底层AI接口封装）
    let runtimeService: any AIRuntimeServing
    /// 提示词工厂：负责构建AI识别需要的专业提示词
    let promptFactory: any MedicalPromptBuilding
    /// 日志器：记录识别过程的关键日志、异常信息
    let logger: Logger

    // MARK: - 初始化方法
    /// 初始化解析器，通过依赖注入传入核心服务
    /// - Parameters:
    ///   - runtimeService: AI运行时服务
    ///   - promptFactory: 医疗提示词构建工厂
    ///   - logger: 日志工具，默认值为控制台日志器
    init(
        runtimeService: any AIRuntimeServing,
        promptFactory: any MedicalPromptBuilding,
        logger: Logger = ConsoleLogger()
    ) {
        self.runtimeService = runtimeService
        self.promptFactory = promptFactory
        self.logger = logger
    }

    // MARK: - 核心对外方法：解析文档类型
    /// 解析医疗文档的类型（核心业务方法）
    /// - Parameters:
    ///   - selectedKind: 用户手动选择的文档类型
    ///   - mergedOCRText: 文档OCR识别后的合并文本
    /// - Returns: 文档类型解析结果
    /// - Throws: 调用AI服务失败时抛出异常
    func resolve(
        selectedKind: MedicalDocumentKind,
        mergedOCRText: String,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> MedicalDocumentTypeResolution {
        try cancellationToken?.checkCancellation()
        logger.info("开始解析医疗文档类型, capability=\(Self.capabilityName), 预选值: \(selectedKind.rawValue)", module: .medical)
        // 1. 优先逻辑：用户手动选择了类型，直接返回结果，置信度100%
        if selectedKind != .auto {
            logger.info("用户手动指定类型: \(selectedKind.rawValue)", module: .medical)
            return MedicalDocumentTypeResolution(
                kind: selectedKind,       // 使用用户手动选择的类型
                confidence: 1,            // 置信度满分
                source: .manual,          // 来源：手动选择
                reason: "manual_selected" // 原因：用户手动选择
            )
        }

        // 2. 次优先逻辑：本地关键词规则匹配，匹配成功直接返回
        if let rules = resolveByRules(text: mergedOCRText) {
            logger.info("本地规则匹配成功: kind=\(rules.kind.rawValue), confidence=\(rules.confidence)", module: .medical)
            return rules
        }

        try cancellationToken?.checkCancellation()
        // 3. 兜底逻辑：规则匹配失败，调用AI大模型进行智能识别
        logger.info("本地规则未命中，触发 AI 大模型识别", module: .medical)
        // 构建AI识别文档类型的提示词
        let prompt = promptFactory.typeRecognitionPrompt(ocrText: mergedOCRText)
        // 调用AI流式接口，获取完整响应文本
        let responseText = try await collectResponseText(
            from: try await runtimeService.generateTextStream(
                request: AIRuntimeTextRequest(
                    scenario: .medicalDocumentTypeRecognition, // 场景：医疗文档类型识别
                    messages: [AIRuntimeMessage(role: .user, content: prompt)], // 传入用户提示词
                    reasoning: .disabled, // 关闭AI推理步骤，仅输出结果
                    cancellationToken: cancellationToken
                )
            ),
            cancellationToken: cancellationToken
        )
        
        // 解析AI返回的结果，解析失败则使用默认值
        let parsed = parseAIResponse(responseText) ?? .init(
            kind: .medicalReport,    // 默认类型：医疗报告
            confidence: 0.4,         // 默认置信度
            source: .ai,             // 来源：AI
            reason: "ai_fallback_default" // 原因：AI解析失败兜底
        )
        
        // 打印日志：记录AI识别结果
        logger.info("AI 类型识别完成，kind=\(parsed.kind.rawValue), confidence=\(parsed.confidence)", module: .medical)
        
        // 返回最终解析结果
        return parsed
    }

    // MARK: - 私有方法：本地规则匹配
    /// 通过关键词规则匹配文档类型（轻量、快速，优先于AI调用）
    /// - Parameter text: OCR识别后的文本
    /// - Returns: 匹配成功返回解析结果，失败返回nil
    private func resolveByRules(text: String) -> MedicalDocumentTypeResolution? {
        let results = LocalMedicalDocumentClassifier.classify(text: text)
        // 记录所有本地规则的原始得分情况，便于后续调整权重
        let debugScores = results.map { "\($0.kind.rawValue):\($0.confidence)" }.joined(separator: ", ")
        logger.debug("本地规则原始得分: [\(debugScores)]", module: .medical)

        // 筛选出置信度>=30的结果
        let validMatches = results.filter { $0.confidence >= 30 }

        // 如果有有效匹配，选择置信度最高的
        if let bestMatch = validMatches.max(by: { $0.confidence < $1.confidence }) {
            // 将0-100分映射到0.0-1.0置信度（非线性映射，高分更严格）
            let normalizedConfidence = normalizeConfidence(bestMatch.confidence)

            // 构造规则匹配的结果
            return MedicalDocumentTypeResolution(
                kind: bestMatch.kind,
                confidence: normalizedConfidence,
                source: .localRules,       // 来源：本地规则
                reason: "advanced_keyword_rules" // 原因：增强关键词匹配
            )
        }

        // 如果没有达到阈值的匹配，但存在低置信度候选，记录日志后返回nil
        let fallback = results.max(by: { $0.confidence < $1.confidence })!
        if fallback.confidence >= 10 {
            logger.debug("本地规则检测到低置信度候选: kind=\(fallback.kind.rawValue), confidence=\(fallback.confidence)", module: .medical)
            // 构造规则匹配的结果
            return MedicalDocumentTypeResolution(
                kind: fallback.kind,
                confidence: normalizeConfidence(fallback.confidence) ,
                source: .localRules,       // 来源：本地规则
                reason: "advanced_keyword_rules" // 原因：增强关键词匹配
            )
        }

        return nil // 无匹配项/得分不足，返回空
    }

    /// 将原始分数（0-100）归一化为置信度（0.0-1.0）
    /// 使用非线性映射：高分段更严格，避免低分误判
    /// - Parameter rawScore: 原始分数 0-100
    /// - Returns: 归一化置信度 0.0-1.0
    private func normalizeConfidence(_ rawScore: Int) -> Double {
        // 基础映射：40分→0.5，60分→0.7，80分→0.9，100分→0.98
        let score = min(100, max(0, rawScore))

        if score >= 80 {
            return 0.9 + Double(score - 80) * 0.004 // 80-100 → 0.9-0.98
        } else if score >= 60 {
            return 0.7 + Double(score - 60) * 0.01  // 60-80 → 0.7-0.9
        } else if score >= 40 {
            return 0.5 + Double(score - 40) * 0.01  // 40-60 → 0.5-0.7
        } else {
            return 0.3 + Double(score) * 0.005      // 0-40 → 0.3-0.5
        }
    }

    // MARK: - 私有方法：解析AI返回结果
    /// 解析AI返回的JSON格式文本，转为业务模型
    /// - Parameter text: AI原始响应文本
    /// - Returns: 解析后的文档类型结果
    private func parseAIResponse(_ text: String) -> MedicalDocumentTypeResolution? {
        // 清洗AI返回的文本：去除markdown代码块、首尾空白字符
        let payload = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 转为UTF8数据，失败则返回nil
        guard let data = payload.data(using: .utf8) else { return nil }

        // 定义AI返回的JSON结构模型（仅解析需要的字段）
        struct Parsed: Decodable {
            let kind: String?       // 文档类型字符串
            let confidence: Double? // 置信度
            let reason: String?     // 识别原因
        }

        // JSON解码，校验必须字段kind存在
        guard let parsed = try? JSONDecoder.default.decode(Parsed.self, from: data),
              let rawKind = parsed.kind else { return nil }

        // 将AI返回的字符串类型映射为系统枚举类型
        let kind = mapKind(rawKind)
        
        // 构造最终结果
        return MedicalDocumentTypeResolution(
            kind: kind,
            confidence: parsed.confidence ?? 0.5, // 无置信度默认0.5
            source: .ai,
            reason: parsed.reason
        )
    }

    /// 将AI返回的类型字符串映射为系统枚举
    /// - Parameter raw: AI返回的原始字符串
    /// - Returns: 标准医疗文档类型枚举
    private func mapKind(_ raw: String) -> MedicalDocumentKind {
        switch raw.lowercased() {
        case "case_document", "casedocument":
            return .caseDocument // 门诊/住院病历
        case "health_exam_report", "healthexamreport":
            return .healthExamReport // 体检报告
        case "prescription":
            return .prescription // 处方
        case "medication", "medication_plan", "medicationplan":
            return .medicationPlan // 用药说明
        case "medicine_box", "medicinebox":
            return .medicineBox // 药品包装/药箱
        default:
            return .medicalReport // 默认：检查/检验报告
        }
    }

    // MARK: - 私有方法：处理AI流式响应
    /// 收集AI流式接口的返回数据，拼接为完整文本
    /// - Parameter stream: AI异步抛出流
    /// - Returns: 拼接后的完整响应文本
    private func collectResponseText(
        from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> String {
        var bufferedText = ""  // 缓存流式增量文本
        var completedText: String? // 最终完整响应文本
        
        // 遍历异步流，处理每一个事件
        for try await event in stream {
            try cancellationToken?.checkCancellation()
            switch event {
            case .textDelta(let delta):
                // 增量文本：追加到缓存
                bufferedText.append(delta)
            case .completed(let response):
                // 完成事件：获取最终完整文本
                completedText = response.text
            case .reasoningDelta, .toolCallDelta:
                // 忽略推理步骤、工具调用事件
                continue
            }
        }
        
        try cancellationToken?.checkCancellation()
        // 优先返回完整响应，无则返回缓存的增量文本
        return completedText ?? bufferedText
    }
}
