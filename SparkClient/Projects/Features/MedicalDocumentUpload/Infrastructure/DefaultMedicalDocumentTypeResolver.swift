import Foundation

// MARK: - 本地医疗文档分类引擎（统一模块）

private struct LocalMedicalDocumentClassifier {
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

        return [
            MatchResult(kind: .caseDocument, isMatch: caseResult.isMatch, confidence: caseResult.confidence),
            MatchResult(kind: .prescription, isMatch: prescriptionResult.isMatch, confidence: prescriptionResult.confidence),
            MatchResult(kind: .healthExamReport, isMatch: healthExamResult.isMatch, confidence: healthExamResult.confidence),
            MatchResult(kind: .medicalReport, isMatch: medicalReportResult.isMatch, confidence: medicalReportResult.confidence)
        ]
    }

    // MARK: - 内部协议定义
    private protocol Detector {
        static var highKeywords: [String] { get }
        static var mediumKeywords: [String] { get }
        static var lowKeywords: [String] { get }
        static var threshold: Int { get }
        static func detect(text: String) -> (isMatch: Bool, confidence: Int)
        static func additionalScoring(on text: String) -> Int
    }

    private static func baseDetect<D: Detector>(
        text: String,
        detectorType: D.Type
    ) -> (isMatch: Bool, confidence: Int) {
        var score = 0

        // A. 高权重匹配 (15分/个)
        for word in detectorType.highKeywords where text.contains(word.lowercased()) {
            score += 15
        }

        // B. 中权重匹配 (2分/个，最高10分)
        let mediumMatchCount = detectorType.mediumKeywords.filter { text.contains($0.lowercased()) }.count
        score += min(mediumMatchCount, 5) * 2

        // C. 低权重匹配 (1分/个，最高8分)
        let lowMatchCount = detectorType.lowKeywords.filter { text.contains($0.lowercased()) }.count
        score += min(lowMatchCount, 8) * 1

        // D. 结构化加分
        score += detectorType.additionalScoring(on: text)

        let confidence = min(100, max(0, score))
        return (confidence >= detectorType.threshold, confidence)
    }

    // MARK: - 1) 检查/检验报告（重点优化检验化验单）
    private struct MedicalReport: Detector {
        static let threshold = 30

        static let highKeywords = [
            "诊断报告单", "检查报告单", "影像表现", "诊断意见", "影像诊断",
            "病理诊断", "彩超检查", "检验报告单", "检验报告", "检测报告"
        ]
        static let mediumKeywords = [
            "检查项目", "检测项目", "检查部位", "报告医生", "审核医生", "超声描述",
            "超声提示", "检查号", "影像号", "标本类型", "标本号", "条码号",
            "检验者", "申请医生", "送检医生", "临床检验"
        ]
        static let lowKeywords = [
            "ct", "mri", "b超", "回声", "结节", "肿块", "占位", "病灶"
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
            if text.contains("检验互认项目") || text.contains("质评合格") {
                extra += 15
            }

            // 排除逻辑
            if text.contains("处方笺") || text.contains("处方单") {
                if !text.contains("检查") && !text.contains("诊断") { extra -= 15 }
            }
            if text.contains("主诉") && text.contains("现病史") { extra -= 20 }

            return extra
        }
    }

    // MARK: - 2) 病历
    private struct CaseDocument: Detector {
        static let threshold = 30
        static let highKeywords = ["门诊病历", "住院病历", "急诊病历", "主诉", "现病史", "既往史", "体格检查", "初步诊断", "处理意见"]
        static let mediumKeywords = ["辅助检查", "过敏史", "个人史", "入院日期", "出院日期", "住院号", "医师签名", "门诊号"]
        static let lowKeywords = ["症状", "体征", "随访", "医嘱", "复诊", "诊断", "治疗"]

        static func detect(text: String) -> (isMatch: Bool, confidence: Int) {
            LocalMedicalDocumentClassifier.baseDetect(text: text, detectorType: Self.self)
        }

        static func additionalScoring(on text: String) -> Int {
            var extra = 0
            if text.contains("病历") && (text.contains("门诊") || text.contains("急诊")) { extra += 50 }
            if text.contains("主诉") && text.contains("现病史") { extra += 20 }
            if text.contains("影像诊断") || text.contains("诊断意见") {
                if !text.contains("初步诊断") && !text.contains("处理意见") { extra -= 15 }
            }
            return extra
        }
    }

    // MARK: - 3) 处方
    private struct Prescription: Detector {
        static let threshold = 30
        static let highKeywords = ["处方笺", "处方单", "处方", "rp", "国药准字", "批准文号", "用法", "用量", "sig"]
        static let mediumKeywords = ["药品名称", "发药清单", "医师签名", "审核", "调配", "tid", "bid", "qd", "qn", "ivgtt"]
        static let lowKeywords = ["片", "粒", "支", "瓶", "盒", "mg", "ml", "每次", "每日"]

        static func detect(text: String) -> (isMatch: Bool, confidence: Int) {
            LocalMedicalDocumentClassifier.baseDetect(text: text, detectorType: Self.self)
        }

        static func additionalScoring(on text: String) -> Int {
            var extra = 0
            if (text.contains("处方") || text.contains("rp")) && (text.contains("用法") || text.contains("sig")) {
                extra += 20
            }
            if text.contains("主诉") && text.contains("现病史") { extra -= 20 }
            if text.contains("检查所见") || text.contains("影像诊断") {
                if !text.contains("处方") && !text.contains("用药") { extra -= 15 }
            }
            return extra
        }
    }

    // MARK: - 4) 体检报告
    private struct HealthExam: Detector {
        static let threshold = 30
        static let highKeywords = ["体检报告", "健康体检", "体检中心", "体检结论", "体检建议", "体检日期", "体检编号", "报告日期"]
        static let mediumKeywords = ["参考范围", "正常范围", "总胆固醇", "甘油三酯", "血红蛋白", "尿素氮", "体检套餐", "体检项目表"]
        static let lowKeywords = ["偏高", "偏低", "建议", "复查", "进一步检查", "定期体检"]

        static func detect(text: String) -> (isMatch: Bool, confidence: Int) {
            LocalMedicalDocumentClassifier.baseDetect(text: text, detectorType: Self.self)
        }

        static func additionalScoring(on text: String) -> Int {
            var extra = 0
            if text.count > 5000 { extra += 10 } else if text.count > 2000 { extra += 5 }
            if text.contains("总结建议") && text.contains("体检中心") { extra += 20 }
            if text.contains("健康体检") || text.contains("导读") { extra += 10 }
            if text.contains("主诉") || text.contains("现病史") { extra -= 20 }
            return extra
        }
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
        mergedOCRText: String
    ) async throws -> MedicalDocumentTypeResolution {
        logger.info("开始解析医疗文档类型, 预选值: \(selectedKind.rawValue)", module: .medical)
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
                    reasoning: .disabled // 关闭AI推理步骤，仅输出结果
                )
            )
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
        if fallback.confidence >= 20 {
            logger.debug("本地规则检测到低置信度候选: kind=\(fallback.kind.rawValue), confidence=\(fallback.confidence)", module: .medical)
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
        guard let parsed = try? JSONDecoder().decode(Parsed.self, from: data),
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
        case "medication":
            return .medication // 用药说明
        default:
            return .medicalReport // 默认：检查/检验报告
        }
    }

    // MARK: - 私有方法：处理AI流式响应
    /// 收集AI流式接口的返回数据，拼接为完整文本
    /// - Parameter stream: AI异步抛出流
    /// - Returns: 拼接后的完整响应文本
    private func collectResponseText(
        from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>
    ) async throws -> String {
        var bufferedText = ""  // 缓存流式增量文本
        var completedText: String? // 最终完整响应文本
        
        // 遍历异步流，处理每一个事件
        for try await event in stream {
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
        
        // 优先返回完整响应，无则返回缓存的增量文本
        return completedText ?? bufferedText
    }
}
