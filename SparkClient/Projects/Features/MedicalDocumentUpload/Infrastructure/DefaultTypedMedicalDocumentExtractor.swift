// 导入Foundation框架，提供基础数据类型、文件、网络、异步等核心功能
import Foundation
// 导入统一类型标识框架，用于判断文件类型（图片/文档等）
import UniformTypeIdentifiers

// MARK: - 错误类型
/// 抽取过程中的错误类型
enum ExtractionError: Error {
    case decodingFailed
    case invalidDebugPayload
}

/// 默认实现的 医疗文档类型化抽取器
/// 核心职责：对上传的医疗文件做 OCR 识别 → 文档类型判定 → AI 抽取结构化数据 → 组装标准输出
/// 遵循 TypedMedicalDocumentExtracting 协议 + Sendable 保证跨异步/线程安全
struct DefaultTypedMedicalDocumentExtractor: TypedMedicalDocumentExtracting, Sendable {
    // MARK: - 依赖注入组件（所有外部能力都通过初始化传入，解耦、可测试）
    /// OCR 编排器：统一处理图片/文档的文字识别（底层封装了不同 OCR 引擎）
    let ocrOrchestrator: OCROrchestrator
    /// 文档类型解析器：根据 OCR 文本判断当前是哪种医疗文档（病例/体检报告/处方等）
    let typeResolver: any MedicalDocumentTypeResolving
    /// AI 提示词工厂：根据文档类型生成对应的抽取 Prompt
    let promptFactory: any MedicalPromptBuilding
    /// AI 运行时服务：调用大模型流式/非流式生成文本
    let runtimeService: any AIRuntimeServing
    /// 日志器：打印 Info/Debug/Warning 日志，方便排查问题
    let logger: Logger
    /// JSON 标准化工具：清洗 AI 返回的 JSON，保证格式统一、可解析
    let jsonNormalizer: MedicalDocumentModelJSONNormalizer

    // MARK: - 初始化器（依赖注入入口）
    /// 初始化医疗文档类型化抽取器
    /// - 所有核心能力通过外部传入，遵循依赖倒置原则，便于单元测试和替换实现
    init(
        ocrOrchestrator: OCROrchestrator,
        typeResolver: any MedicalDocumentTypeResolving,
        promptFactory: any MedicalPromptBuilding,
        runtimeService: any AIRuntimeServing,
        // 日志器提供默认值：控制台日志
        logger: Logger = ConsoleLogger(),
        // JSON 标准化工具提供默认实例
        jsonNormalizer: MedicalDocumentModelJSONNormalizer = .init()
    ) {
        // 赋值所有依赖
        self.ocrOrchestrator = ocrOrchestrator
        self.typeResolver = typeResolver
        self.promptFactory = promptFactory
        self.runtimeService = runtimeService
        self.logger = logger
        self.jsonNormalizer = jsonNormalizer
    }

    // MARK: - 对外暴露的核心抽取方法（业务主入口）
    /// 对外核心方法：执行 医疗文档 类型化信息抽取
    /// - Parameters:
    ///   - memberID: 用户/会员ID，用于标识归属
    ///   - files: 本次上传的本地文件列表（可能多张图片/多个PDF）
    ///   - selectedKind: 用户手动选择的文档类型（辅助AI更精准识别）
    /// - Returns: 标准化的类型化抽取结果（包含原始OCR、类型判定、结构化数据、预览JSON）
    /// - Throws: 任意环节抛出错误都会向上抛出（OCR失败/AI调用失败/JSON解析失败）
    func extract(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        selectedKind: MedicalDocumentKind
    ) async throws -> MedicalDocumentTypedExtractionOutput {
//#if DEBUG
//        logger.info("使用本地 Debug 假装抽取病例数据（跳过 OCR/AI）", module: .medical)
//        return try makeDebugPretendCaseOutput(memberID: memberID, files: files)
//#endif
        // 1. 对所有上传文件执行OCR，并把所有文本合并成一段完整文本
        let mergedOCR = try await buildMergedOCRText(files: files)
        
        // 2. 根据用户选择类型 + OCR文本，最终确定文档类型（病例/体检/处方等）
        let resolution = try await typeResolver.resolve(selectedKind: selectedKind, mergedOCRText: mergedOCR)
        // 解析出最终判定的文档类型
        let kind = resolution.kind
        
        // 3. 根据文档类型，生成对应的AI抽取提示词（Prompt）
        let prompt = promptFactory.extractionPrompt(for: MedicalPromptInput(kind: kind, mergedOCRText: mergedOCR))
        
        // 4. 调用AI，执行结构化抽取，得到类型化结果 + 标准JSON
        let extraction = try await extractTypedResult(kind: kind, prompt: prompt)
        let extractedJSON = extraction.json
        
        // 5. 构建识别信封：保存本次抽取的所有原始信息（用于溯源、审计、重试）
        let envelope = MedicalDocumentRecognitionEnvelope(
            memberID: memberID,
            sourceFiles: files,
            rawOCRText: mergedOCR,
            typeResolution: resolution
        )
        
        // 6. 构建日志/预览用的JSON字符串（方便查看结果）
        let preview = """
        {
          "memberID": \(memberID),
          "kind": "\(kind.rawValue)",
          "resolutionSource": "\(resolution.source.rawValue)",
          "confidence": \(String(format: "%.2f", resolution.confidence)),
          "payload": \(extractedJSON)
        }
        """
        
        // 7. 打印日志：标记类型抽取完成
        logger.info("typed 抽取完成，kind=\(kind.rawValue)", module: .medical)
        
        // 8. 返回最终标准化输出对象
        return MedicalDocumentTypedExtractionOutput(
            envelope: envelope,
            typedResult: extraction.typed,
            extractedJSON: extractedJSON,
            payloadPreview: preview
        )
    }

    // MARK: - 根据文档类型执行对应结构化抽取
    /// 私有方法：根据文档类型，执行AI结构化抽取，直接获取领域模型
    /// - Parameters:
    ///   - kind: 最终判定的文档类型
    ///   - prompt: AI抽取提示词
    /// - Returns: 元组：(业务层类型结果, 标准JSON字符串)
    /// - Throws: AI调用失败、解析失败
    private func extractTypedResult(
        kind: MedicalDocumentKind,
        prompt: String
    ) async throws -> (typed: MedicalDocumentTypedResult, json: String) {
        // 根据不同文档类型，走不同的抽取&解析流程
        switch kind {
        // 病例文档
        case .caseDocument:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .medicalCaseExtraction,
                kindLabel: "case_document",
                as: CaseRecognitionDraft.self
            )
            guard let draft = final.decoded else {
                throw ExtractionError.decodingFailed
            }
            return (.caseDocument(draft), final.normalizedJSON)

        // 体检报告
        case .healthExamReport:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .healthExamExtraction,
                kindLabel: "health_exam_report",
                as: HealthExamRecognitionDraft.self
            )
            guard let draft = final.decoded else {
                throw ExtractionError.decodingFailed
            }
            return (.healthExamReport(draft), final.normalizedJSON)

        // 医疗报告 / 自动识别
        case .medicalReport, .auto:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .medicalReportExtraction,
                kindLabel: "medical_report",
                as: [MedicalReportRecognitionDraft].self
            )
            guard let draft = final.decoded else {
                throw ExtractionError.decodingFailed
            }
            return (.medicalReport(draft), final.normalizedJSON)

        // 处方单
        case .prescription:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .prescriptionExtraction,
                kindLabel: "prescription",
                as: PrescriptionRecognitionDraft.self
            )
            guard let draft = final.decoded else {
                throw ExtractionError.decodingFailed
            }
            return (.prescription(draft), final.normalizedJSON)

        // 用药单
        case .medication:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .medicationExtraction,
                kindLabel: "medication",
                as: [MedicationRecognitionDraft].self
            )
            guard let draft = final.decoded else {
                throw ExtractionError.decodingFailed
            }
            return (.medication(draft), final.normalizedJSON)
        }
    }

    // MARK: - AI 流式结构化抽取通用方法
    /// 通用结构化抽取方法：调用AI流式生成 → 解码JSON → 返回标准化结果
    /// - Parameters:
    ///   - prompt: 提示词
    ///   - scenario: AI场景（用于后台统计、限流、模型路由）
    ///   - kindLabel: 文档类型标识（日志/监控用）
    ///   - type: 要解析的目标Decodable模型
    /// - Returns: 流式解析最终结果（包含解码对象+标准化JSON）
    /// - Throws: AI调用异常、解析异常
    private func extractStructured<T: Decodable>(
        prompt: String,
        scenario: AIScenario,
        kindLabel: String,
        as type: T.Type
    ) async throws -> StructuredJSONStreamFinal<T> {
        // 1. 调用AI运行时，获取流式输出流
        let stream = try await runtimeService.generateTextStream(
            request: AIRuntimeTextRequest(
                scenario: scenario,
                messages: [AIRuntimeMessage(role: .user, content: prompt)],
                reasoning: .disabled // 关闭推理加速，保证输出稳定JSON
            )
        )
        
        // 2. 创建流式JSON解码器（自动清洗、容错、标准化）
        let decoder = StructuredJSONStreamDecoder<T>(normalizer: jsonNormalizer, logger: logger, kindLabel: kindLabel)
        
        // 3. 收集完整流并解析成目标对象
        let final = try await decoder.collect(from: stream)
        
        // 4. 日志：记录解码成功/失败
        if final.decoded == nil {
            logger.warning("文档 JSON 解码失败，kind=\(kindLabel)", module: .medical)
        } else {
            logger.debug("文档 JSON 解码成功，kind=\(kindLabel)", module: .medical)
        }
        
        return final
    }

    // MARK: - OCR 合并处理
    /// 私有方法：遍历所有文件 → 执行OCR → 拼接成一段完整文本
    private func buildMergedOCRText(files: [MedicalUploadLocalFile]) async throws -> String {
        var chunks: [String] = []
        // 遍历文件，逐个识别
        for (idx, file) in files.enumerated() {
            let ocr = try await recognize(file: file)
            // 给每个文件的OCR加标题分隔，方便AI区分来源
            chunks.append("=== File \(idx + 1): \(file.displayName) ===\n\(ocr.text)")
        }
        // 用换行拼接所有文本
        return chunks.joined(separator: "\n\n")
    }

    /// 对单个文件执行OCR（自动区分图片/文档）
    private func recognize(file: MedicalUploadLocalFile) async throws -> OCRRecognition {
        // 判断是否是图片
        if isImage(url: file.url, mimeType: file.mimeType) {
            let data = try Data(contentsOf: file.url)
            // 图片OCR
            return try await ocrOrchestrator.recognize(imageData: data, options: .medicalDefault)
        }
        // 文档OCR（PDF等）
        return try await ocrOrchestrator.recognize(document: file.url, options: .medicalDefault)
    }

    /// 判断文件是否为图片（通过MIME类型 / 文件后缀）
    private func isImage(url: URL, mimeType: String?) -> Bool {
        // 方式1：根据MIME类型判断
        if let mimeType, let type = UTType(mimeType: mimeType), type.conforms(to: .image) {
            return true
        }
        // 方式2：根据后缀名判断
        if let extType = UTType(filenameExtension: url.pathExtension), extType.conforms(to: .image) {
            return true
        }
        return false
    }

}

#if DEBUG
private extension DefaultTypedMedicalDocumentExtractor {
    struct DebugPretendEnvelope: Decodable {
        let kind: MedicalDocumentKind
        let resolutionSource: MedicalDocumentTypeResolution.Source
        let confidence: Double
        let payload: CaseRecognitionDraft
    }

    func makeDebugPretendCaseOutput(
        memberID: Int,
        files: [MedicalUploadLocalFile]
    ) throws -> MedicalDocumentTypedExtractionOutput {
        guard let data = Self.debugPretendCaseJSON.data(using: .utf8) else {
            throw ExtractionError.invalidDebugPayload
        }
        let decoder = JSONDecoder()
        let envelopePayload = try decoder.decode(DebugPretendEnvelope.self, from: data)
        let payloadJSON = try prettyJSONString(from: envelopePayload.payload)
        let preview = """
        {
          "memberID": \(memberID),
          "kind": "\(envelopePayload.kind.rawValue)",
          "resolutionSource": "\(envelopePayload.resolutionSource.rawValue)",
          "confidence": \(String(format: "%.2f", envelopePayload.confidence)),
          "payload": \(payloadJSON)
        }
        """
        let envelope = MedicalDocumentRecognitionEnvelope(
            memberID: memberID,
            sourceFiles: files,
            rawOCRText: "[DEBUG] pretend case extraction bypassed OCR",
            typeResolution: MedicalDocumentTypeResolution(
                kind: envelopePayload.kind,
                confidence: envelopePayload.confidence,
                source: envelopePayload.resolutionSource,
                reason: "debug pretend case extraction"
            )
        )
        return MedicalDocumentTypedExtractionOutput(
            envelope: envelope,
            typedResult: .caseDocument(envelopePayload.payload),
            extractedJSON: payloadJSON,
            payloadPreview: preview
        )
    }

    func prettyJSONString<T: Encodable>(from value: T) throws -> String {
        let text = try JSONPayloadFormatting.prettyString(from: value)
        guard text != "<empty>", text.hasPrefix("<非 UTF-8") == false else {
            throw ExtractionError.invalidDebugPayload
        }
        return text
    }

    static let debugPretendCaseJSON = """
    {
        "memberID": 13,
        "kind": "caseDocument",
        "resolutionSource": "localRules",
        "confidence": 0.98,
        "payload": {
            "title": "就诊病例",
            "summary": "患者芦超28岁于2025/06/21在苏州工业园区星塘医院妇产科就诊，诊断念珠菌性外阴阴道炎；患者赵道凯1998/10/29出生，2026-02-06在苏州大学附属第四医院口腔科门诊初诊，要求口腔检查1天，专科检查见38/48近中低位阻生，远中牙龈覆盖，龈红肿，诊断阻生牙K01.100，建议择期拔除；2025-12-28赵道凯在苏州大学附属第四医院行生化检验、肾功能检验，结果大致正常。",
            "diagnosis": "念珠菌性外阴阴道炎；阻生牙K01.100",
            "hospitalName": "苏州工业园区星塘医院;苏州大学附属第四医院（苏州市独墅湖医院）",
            "ageAtVisit": "28;27岁1月",
            "occurredAt": "2025-06-21;2026-02-06;2025-12-28",
            "symptom": {
                "name": "口腔检查要求"
            },
            "visit": {
                "visitType": "门诊",
                "visitedAt": "2025-06-21",
                "department": "妇产科（普通）",
                "visitNo": "1681884"
            },
            "prescriptionBatches": [
                {
                    "prescriberName": "未明确",
                    "institutionName": "苏州工业园区星塘医院",
                    "prescribedAt": "2025-06-21",
                    "diagnosis": "念珠菌性外阴阴道炎",
                    "batchNo": "1681884",
                    "medications": [
                        {
                            "genericName": "卢立康唑乳膏",
                            "brandName": "路利特",
                            "drugName": "卢立康唑乳膏（路利特）",
                            "dosageForm": "乳膏剂",
                            "strength": "5g:50mg（1%）",
                            "route": "外用",
                            "dosePerTime": "1g/次",
                            "doseValue": "1",
                            "doseUnit": "g",
                            "frequencyCode": "bid",
                            "period": "日",
                            "timesPerPeriod": "2",
                            "frequencyText": "每天2次",
                            "durationDays": "未明确",
                            "instructions": "外用 每天2次1g/次"
                        },
                        {
                            "genericName": "克霉唑阴道膨胀栓",
                            "brandName": "未明确",
                            "drugName": "克霉唑阴道膨胀栓",
                            "dosageForm": "栓剂",
                            "strength": "未明确",
                            "route": "阴塞",
                            "dosePerTime": "1粒/次",
                            "doseValue": "1",
                            "doseUnit": "粒",
                            "frequencyCode": "qd",
                            "period": "日",
                            "timesPerPeriod": "1",
                            "frequencyText": "每天1次",
                            "durationDays": "未明确",
                            "instructions": "阴塞 每天1次1粒/次"
                        },
                        {
                            "genericName": "伊曲康唑分散片",
                            "brandName": "未明确",
                            "drugName": "伊曲康唑分散片",
                            "dosageForm": "片剂",
                            "strength": "0.1g*14片",
                            "route": "口服",
                            "dosePerTime": "2片/次",
                            "doseValue": "2",
                            "doseUnit": "片",
                            "frequencyCode": "qd",
                            "period": "日",
                            "timesPerPeriod": "1",
                            "frequencyText": "每天1次",
                            "durationDays": "未明确",
                            "instructions": "口服 每天1次2片/次"
                        }
                    ]
                }
            ],
            "examinationReports": [
                {
                    "reportType": "检验报告",
                    "title": "苏州大学附属第四医院检验报告单",
                    "hospital": "苏州大学附属第四医院（苏州市独墅湖医院）",
                    "doctor": "朱孝明;魏和轩;王一發;魏雨轩;王一斐",
                    "content": "罗氏Cobas 8000检验报告，采样时间2025-12-28 09:24，核收时间2025-12-28 10:08，报告时间2025-12-28 10:48，送检项目为生化检验、肾功能检，结果显示总胆红素13.5≤26、直接胆红素4.2≤8、间接胆红素9.3、天门冬氨酸氨基转移酶13.51、丙氨酸氨基转移酶14.6、总蛋白77.0、白蛋白47.4、球蛋白29.6、白蛋白/球蛋白1.6、Y-谷氨酰转肽隊19.9、碱性磷酸酶75.9、前白蛋白287.0、尿素5.14、肌酐77.50、尿酸324.6、胱抑素C0.76、葡萄糖5.42、肌酸激酶104.3、乳酸脱氢酶168.0120--250U/L、a-羟丁酸脱氢酶140.472--182U/L、胆碱酯酶11124、甘油三酯0.70适宜：＜1.70mmol/L、总胆固醇51.07适宜：＜5.18mmol/L、高密度脂蛋白胆固醇1.51≥1.04mmol/L、低密度脂蛋白胆固醇3.511理想：≤2.60mmol/L，结果解释符合《中国血脂管理指南2023》相关标准。",
                    "date": "2025-12-28",
                    "details": [
                        {
                            "category": "生化检验",
                            "subCategory": "胆红素代谢",
                            "itemName": "总胆红素",
                            "resultValue": "13.5",
                            "unit": "未明确",
                            "referenceRange": "≤26"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "胆红素代谢",
                            "itemName": "直接胆红素",
                            "resultValue": "4.2",
                            "unit": "未明确",
                            "referenceRange": "≤8"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "胆红素代谢",
                            "itemName": "间接胆红素",
                            "resultValue": "9.3",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肝功能",
                            "itemName": "天门冬氨酸氨基转移酶",
                            "resultValue": "13.51",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肝功能",
                            "itemName": "丙氨酸氨基转移酶",
                            "resultValue": "14.6",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肝功能",
                            "itemName": "总蛋白",
                            "resultValue": "77.0",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肝功能",
                            "itemName": "白蛋白",
                            "resultValue": "47.4",
                            "unit": "未明确",
                            "referenceRange": "40"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肝功能",
                            "itemName": "球蛋白",
                            "resultValue": "29.6",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肝功能",
                            "itemName": "白蛋白/球蛋白",
                            "resultValue": "1.6",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肝功能",
                            "itemName": "Y-谷氨酰转肽隊",
                            "resultValue": "19.9",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肝功能",
                            "itemName": "碱性磷酸酶",
                            "resultValue": "75.9",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肝功能",
                            "itemName": "前白蛋白",
                            "resultValue": "287.0",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肾功能",
                            "itemName": "尿素",
                            "resultValue": "5.14",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肾功能",
                            "itemName": "肌酐",
                            "resultValue": "77.50",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肾功能",
                            "itemName": "尿酸",
                            "resultValue": "324.6",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "肾功能",
                            "itemName": "胱抑素C",
                            "resultValue": "0.76",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "代谢类",
                            "itemName": "葡萄糖",
                            "resultValue": "5.42",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "心肌酶",
                            "itemName": "肌酸激酶",
                            "resultValue": "104.3",
                            "unit": "未明确",
                            "referenceRange": "未明确"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "心肌酶",
                            "itemName": "乳酸脱氢酶",
                            "resultValue": "168.0",
                            "unit": "U/L",
                            "referenceRange": "120--250"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "心肌酶",
                            "itemName": "a-羟丁酸脱氢酶",
                            "resultValue": "140.4",
                            "unit": "U/L",
                            "referenceRange": "72--182"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "心肌酶",
                            "itemName": "胆碱酯酶",
                            "resultValue": "11124",
                            "unit": "U/L",
                            "referenceRange": "儿童、男性"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "血脂",
                            "itemName": "甘油三酯",
                            "resultValue": "0.70",
                            "unit": "mmol/L",
                            "referenceRange": "适宜：＜1.70"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "血脂",
                            "itemName": "总胆固醇",
                            "resultValue": "51.07",
                            "unit": "mmol/L",
                            "referenceRange": "适宜：＜5.18"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "血脂",
                            "itemName": "高密度脂蛋白胆固醇",
                            "resultValue": "1.51",
                            "unit": "mmol/L",
                            "referenceRange": "≥1.04"
                        },
                        {
                            "category": "生化检验",
                            "subCategory": "血脂",
                            "itemName": "低密度脂蛋白胆固醇",
                            "resultValue": "3.511",
                            "unit": "mol/L",
                            "referenceRange": "理想：≤2.60"
                        }
                    ]
                }
            ]
        }
    }
    """
}
#endif
