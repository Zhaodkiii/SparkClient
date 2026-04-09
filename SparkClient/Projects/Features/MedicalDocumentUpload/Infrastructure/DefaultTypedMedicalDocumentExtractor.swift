// 导入Foundation框架，提供基础数据类型、文件、网络、异步等核心功能
import Foundation
// 导入统一类型标识框架，用于判断文件类型（图片/文档等）
import UniformTypeIdentifiers

// MARK: - 错误类型
/// 抽取过程中的错误类型
enum ExtractionError: Error {
    case decodingFailed
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
        logger.info("typed 抽取完成，kind=\(kind.rawValue)", category: "medical_upload")
        
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
                as: MedicationRecognitionDraft.self
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
            logger.warning("文档 JSON 解码失败，kind=\(kindLabel)", category: "medical_upload")
        } else {
            logger.debug("文档 JSON 解码成功，kind=\(kindLabel)", category: "medical_upload")
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
