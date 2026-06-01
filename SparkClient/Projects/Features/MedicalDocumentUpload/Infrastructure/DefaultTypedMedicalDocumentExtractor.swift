// 导入Foundation框架，提供基础数据类型、文件、网络、异步等核心功能
import Foundation
// 导入统一类型标识框架，用于判断文件类型（图片/文档等）
import UniformTypeIdentifiers

// MARK: - 错误类型
/// 抽取过程中的错误类型
enum ExtractionError: Error {
    case decodingFailed(context: StructuredJSONDecodingFailureContext?)
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
        selectedKind: MedicalDocumentKind,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> MedicalDocumentTypedExtractionOutput {
//#if DEBUG
//        logger.info("使用本地 Debug 假装结构化抽取（跳过 OCR/AI），selectedKind=\(selectedKind.rawValue)", module: .medical)
//        return try makeDebugPretendOutput(memberID: memberID, files: files, selectedKind: selectedKind)
//#else
        try cancellationToken?.checkCancellation()
        logger.info("typed 抽取开始，文件数=\(files.count), selectedKind=\(selectedKind.rawValue)", module: .medical)

        // 1. 对所有上传文件执行OCR，并把所有文本合并成一段完整文本
        let mergedOCR = try await mergeOCRText(files: files, reRecognizeAll: false, cancellationToken: cancellationToken)
        try cancellationToken?.checkCancellation()
        
        // 2. 根据用户选择类型 + OCR文本，最终确定文档类型（病例/体检/处方等）
        let resolution = try await resolveType(
            selectedKind: selectedKind,
            mergedOCRText: mergedOCR,
            cancellationToken: cancellationToken
        )
        try cancellationToken?.checkCancellation()

        return try await extractStructured(
            memberID: memberID,
            files: files,
            mergedOCRText: mergedOCR,
            resolution: resolution,
            preferredModelName: nil,
            retryFeedback: nil,
            cancellationToken: cancellationToken
        )
//#endif
    }

    func mergeOCRText(
        files: [MedicalUploadLocalFile],
        reRecognizeAll: Bool = false,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> String {
        let filesWithOCR = try await recognizeOCRFiles(
            files: files,
            reRecognizeAll: reRecognizeAll,
            cancellationToken: cancellationToken
        )
        return buildMergedOCRText(files: filesWithOCR)
    }

    func recognizeOCRFiles(
        files: [MedicalUploadLocalFile],
        reRecognizeAll: Bool = false,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> [MedicalUploadLocalFile] {
        var output: [MedicalUploadLocalFile] = []
        var recognizedCount = 0
        var skippedCount = 0
        for (idx, file) in files.enumerated() {
            try cancellationToken?.checkCancellation()
            if reRecognizeAll == false, let ocrText = file.ocrText, ocrText.isEmpty == false {
                logger.info(
                    "已有 OCR 记录，跳过识别 fileIndex=\(idx + 1)/\(files.count) name=\(file.displayName)",
                    module: .medical
                )
                output.append(file)
                skippedCount += 1
                continue
            }
            logger.info("开始 OCR 识别 fileIndex=\(idx + 1)/\(files.count) name=\(file.displayName)", module: .medical)
            let ocr = try await recognize(file: file)
            try cancellationToken?.checkCancellation()
            output.append(file.withOCRText(ocr.text))
            recognizedCount += 1
        }
        logger.info(
            "单文件 OCR 完成，total=\(output.count) 新识别=\(recognizedCount) 跳过=\(skippedCount)",
            module: .medical
        )
        return output
    }

    func resolveType(
        selectedKind: MedicalDocumentKind,
        mergedOCRText: String,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> MedicalDocumentTypeResolution {
        try await typeResolver.resolve(
            selectedKind: selectedKind,
            mergedOCRText: mergedOCRText,
            cancellationToken: cancellationToken
        )
    }

    func extractStructured(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        mergedOCRText: String,
        resolution: MedicalDocumentTypeResolution,
        preferredModelName: String? = nil,
        retryFeedback: MedicalExtractionRetryFeedback? = nil,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> MedicalDocumentTypedExtractionOutput {
        try cancellationToken?.checkCancellation()
        let kind = resolution.kind
//#if DEBUG
//        logger.info("使用本地 Debug 假装抽取病例数据（跳过 OCR/AI）", module: .medical)
//        return try makeDebugPretendCaseOutput(memberID: memberID, files: files, selectedKind: kind)
//#endif
        
        // 3. 根据文档类型，生成对应的AI抽取提示词（Prompt）
        let prompt = promptFactory.extractionPrompt(
            for: MedicalPromptInput(
                kind: kind,
                mergedOCRText: mergedOCRText,
                retryFeedback: retryFeedback
            )
        )
        
        // 4. 调用AI，执行结构化抽取，得到类型化结果 + 标准JSON
        let extraction = try await extractTypedResult(
            kind: kind,
            prompt: prompt,
            preferredModelName: preferredModelName,
            cancellationToken: cancellationToken
        )
        let extractedJSON = extraction.json
        
        // 5. 构建识别信封：保存本次抽取的所有原始信息（用于溯源、审计、重试）
        let envelope = MedicalDocumentRecognitionEnvelope(
            memberID: memberID,
            sourceFiles: files,
            rawOCRText: mergedOCRText,
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

    // MARK: - 对话工具：从提炼文本抽取（与上传共用 `extractTypedResult` / Prompt / 场景）
    /// 供 `generate_structured_health_card` 调用：无 OCR、无本地文件，`raw_text` 即模型提炼后的医学摘录。
    /// - `report_type`：`medication_plan` / `medicine_box` / `prescription` / `exam_report` / `medical_case`（兼容别名 `medication`）。
    func extractFromChatDistilledText(
        memberID: Int?,
        reportType: String,
        rawText: String
    ) async throws -> MedicalDocumentTypedExtractionOutput {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ExtractionError.decodingFailed(context: nil)
        }
        let kind = Self.medicalDocumentKind(fromChatReportType: reportType)
        let resolution = MedicalDocumentTypeResolution(
            kind: kind,
            confidence: 1.0,
            source: .manual,
            reason: "chat_tool:\(reportType)"
        )
        let envelope = MedicalDocumentRecognitionEnvelope(
            memberID: memberID,
            sourceFiles: [],
            rawOCRText: trimmed,
            typeResolution: resolution
        )
        let prompt = promptFactory.extractionPrompt(for: MedicalPromptInput(kind: kind, mergedOCRText: trimmed))
        let extraction = try await extractTypedResult(kind: kind, prompt: prompt, cancellationToken: nil)
        let extractedJSON = Self.normalizedExtractedJSON(for: extraction.typed, fallback: extraction.json)
        let preview = """
        {
          "memberID": \(memberID),
          "kind": "\(kind.rawValue)",
          "reportType": "\(reportType)",
          "payload": \(extractedJSON)
        }
        """
        logger.info("chat 医疗工具抽取完成，kind=\(kind.rawValue)", module: .medical)
        return MedicalDocumentTypedExtractionOutput(
            envelope: envelope,
            typedResult: extraction.typed,
            extractedJSON: extractedJSON,
            payloadPreview: preview
        )
    }

    /// 与 `HealthClient` `generate_structured_health_card` 的 `report_type` 对齐。
    private static func medicalDocumentKind(fromChatReportType raw: String) -> MedicalDocumentKind {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "medication", "medication_plan", "medicationplan": return .medicationPlan
        case "medicine_box", "medicinebox": return .medicineBox
        case "prescription": return .prescription
        case "exam_report": return .medicalReport
        case "medical_case": return .caseDocument
        default: return .medicalReport
        }
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
        prompt: String,
        preferredModelName: String? = nil,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> (typed: MedicalDocumentTypedResult, json: String) {
        try cancellationToken?.checkCancellation()
//#if DEBUG
//        logger.info("使用本地 Debug 假装结构化抽取（跳过 AI），kind=\(kind.rawValue)", module: .medical)
//        return try makeDebugPretendTypedResult(kind: kind)
//#endif
//        
        // 根据不同文档类型，走不同的抽取&解析流程
        switch kind {
        // 病例文档
        case .caseDocument:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .medicalCaseExtraction,
                kindLabel: "case_document",
                as: CaseRecognitionDraft.self,
                preferredModelName: preferredModelName,
                cancellationToken: cancellationToken
            )
            guard let draft = final.decoded else {
                throw Self.decodingFailedError(from: final, kindLabel: "case_document")
            }
            let normalized = Self.normalizedCaseDraft(draft)
            return (.caseDocument(normalized), Self.normalizedExtractedJSON(for: .caseDocument(normalized), fallback: final.normalizedJSON))

        // 体检报告
        case .healthExamReport:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .healthExamExtraction,
                kindLabel: "health_exam_report",
                as: HealthExamRecognitionDraft.self,
                preferredModelName: preferredModelName,
                cancellationToken: cancellationToken
            )
            guard let draft = final.decoded else {
                throw Self.decodingFailedError(from: final, kindLabel: "health_exam_report")
            }
            return (.healthExamReport(draft), final.normalizedJSON)

        // 医疗报告 / 自动识别
        case .medicalReport, .auto:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .medicalReportExtraction,
                kindLabel: "medical_report",
                as: [MedicalReportRecognitionDraft].self,
                preferredModelName: preferredModelName,
                cancellationToken: cancellationToken
            )
            guard let draft = final.decoded else {
                throw Self.decodingFailedError(from: final, kindLabel: "medical_report")
            }
            return (.medicalReport(draft), final.normalizedJSON)

        // 处方单
        case .prescription:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .prescriptionExtraction,
                kindLabel: "prescription",
                as: PrescriptionRecognitionDraft.self,
                preferredModelName: preferredModelName,
                cancellationToken: cancellationToken
            )
            guard let draft = final.decoded else {
                throw Self.decodingFailedError(from: final, kindLabel: "prescription")
            }
            let normalized = Self.normalizedPrescriptionDraft(draft)
            return (.prescription(normalized), Self.normalizedExtractedJSON(for: .prescription(normalized), fallback: final.normalizedJSON))

        // 用药单
        case .medicationPlan:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .medicationExtraction,
                kindLabel: "medication",
                as: [MedicationPlanRecognitionDraft].self,
                preferredModelName: preferredModelName,
                cancellationToken: cancellationToken
            )
            guard let draft = final.decoded else {
                throw Self.decodingFailedError(from: final, kindLabel: "medication")
            }
            let plans = Self.normalizedMedicationPlanDrafts(draft)
            return (.medicationPlan(plans), Self.normalizedExtractedJSON(for: .medicationPlan(plans), fallback: final.normalizedJSON))

        case .medicineBox:
            let final = try await extractStructured(
                prompt: prompt,
                scenario: .medicineBoxExtraction,
                kindLabel: "medicine_box",
                as: [MedicineBoxRecognitionDraft].self,
                preferredModelName: preferredModelName,
                cancellationToken: cancellationToken
            )
            guard let draft = final.decoded else {
                throw Self.decodingFailedError(from: final, kindLabel: "medicine_box")
            }
            return (.medicineBoxes(draft), final.normalizedJSON)
        }
    }

    private static func decodingFailedError<T>(
        from final: StructuredJSONStreamFinal<T>,
        kindLabel: String
    ) -> ExtractionError {
        .decodingFailed(
            context: StructuredJSONDecodingFailureContext(
                error: final.lastDecodingError ?? ExtractionError.decodingFailed(context: nil),
                outputPreview: truncatedOutputPreview(final.normalizedJSON),
                kindLabel: kindLabel
            )
        )
    }

    private static func truncatedOutputPreview(_ text: String, limit: Int = 1200) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<end])
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
        as type: T.Type,
        preferredModelName: String? = nil,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> StructuredJSONStreamFinal<T> {
        try cancellationToken?.checkCancellation()
        logger.info("开始 AI 结构化抽取，kind=\(kindLabel)", module: .medical)
        // 1. 调用AI运行时，获取流式输出流
        let stream = try await runtimeService.generateTextStream(
            request: AIRuntimeTextRequest(
                scenario: scenario,
                messages: [AIRuntimeMessage(role: .user, content: prompt)],
                reasoning: .disabled, // 关闭推理加速，保证输出稳定JSON
                preferredModelName: preferredModelName,
                cancellationToken: cancellationToken
            )
        )
        
        // 2. 创建流式JSON解码器（自动清洗、容错、标准化）
        let decoder = StructuredJSONStreamDecoder<T>(normalizer: jsonNormalizer, logger: logger, kindLabel: kindLabel)
        
        // 3. 收集完整流并解析成目标对象
        let final = try await decoder.collect(from: stream, cancellationToken: cancellationToken)
        
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
    private func buildMergedOCRText(files: [MedicalUploadLocalFile]) -> String {
        var chunks: [String] = []
        for (idx, file) in files.enumerated() {
            // 给每个文件的OCR加标题分隔，方便AI区分来源
            chunks.append("=== File \(idx + 1): \(file.displayName) ===\n\(file.ocrText ?? "")")
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

    // MARK: - reminderTimes 规范化（抽取后统一为 `[{ "time": "HH:mm", "dose": … }]`）

    private static func normalizedMedicationPlanDrafts(
        _ drafts: [MedicationPlanRecognitionDraft]
    ) -> [MedicationPlanRecognitionDraft] {
        drafts.map { draft in
            var next = draft
            next.reminderTimes = .normalized(from: draft.reminderTimes)
            return next
        }
    }

    private static func normalizedPrescriptionDraft(_ draft: PrescriptionRecognitionDraft) -> PrescriptionRecognitionDraft {
        var next = draft
        if var plans = next.medicationPlans {
            plans = normalizedMedicationPlanDrafts(plans)
            next.medicationPlans = plans
        }
        return next
    }

    private static func normalizedCaseDraft(_ draft: CaseRecognitionDraft) -> CaseRecognitionDraft {
        var next = draft
        if var prescriptions = next.prescriptions {
            prescriptions = prescriptions.map { normalizedPrescriptionDraft($0) }
            next.prescriptions = prescriptions
        }
        return next
    }

    private static func normalizedExtractedJSON(
        for typed: MedicalDocumentTypedResult,
        fallback: String
    ) -> String {
        let encoder = JSONEncoder.default
        let data: Data?
        switch typed {
        case .caseDocument(let draft):
            data = try? encoder.encode(draft)
        case .healthExamReport(let draft):
            data = try? encoder.encode(draft)
        case .medicalReport(let drafts):
            data = try? encoder.encode(drafts)
        case .prescription(let draft):
            data = try? encoder.encode(draft)
        case .medicationPlan(let drafts):
            data = try? encoder.encode(drafts)
        case .medicineBoxes(let drafts):
            data = try? encoder.encode(drafts)
        }
        guard let data, let text = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return text
    }

}

#if DEBUG
private extension DefaultTypedMedicalDocumentExtractor {
    func makeDebugPretendOutput(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        selectedKind: MedicalDocumentKind
    ) throws -> MedicalDocumentTypedExtractionOutput {
        let debugKind = Self.debugResolvedKind(for: selectedKind)
        let extraction = try makeDebugPretendTypedResult(kind: debugKind)
        let preview = """
        {
          "memberID": \(memberID),
          "kind": "\(debugKind.rawValue)",
          "resolutionSource": "\(MedicalDocumentTypeResolution.Source.manual.rawValue)",
          "confidence": \(String(format: "%.2f", 1.0)),
          "payload": \(extraction.json)
        }
        """
        let envelope = MedicalDocumentRecognitionEnvelope(
            memberID: memberID,
            sourceFiles: files,
            rawOCRText: "[DEBUG] pretend \(debugKind.rawValue) extraction bypassed OCR",
            typeResolution: MedicalDocumentTypeResolution(
                kind: debugKind,
                confidence: 1.0,
                source: .manual,
                reason: "debug pretend \(debugKind.rawValue) extraction"
            )
        )
        return MedicalDocumentTypedExtractionOutput(
            envelope: envelope,
            typedResult: extraction.typed,
            extractedJSON: extraction.json,
            payloadPreview: preview
        )
    }

    func makeDebugPretendTypedResult(
        kind: MedicalDocumentKind
    ) throws -> (typed: MedicalDocumentTypedResult, json: String) {
        switch Self.debugResolvedKind(for: kind) {
        case .caseDocument:
            let payload: CaseRecognitionDraft = try decodeDebugPayload(Self.debugPretendCaseJSON)
            return (.caseDocument(payload), try prettyJSONString(from: payload))

        case .healthExamReport:
            let payload: HealthExamRecognitionDraft = try decodeDebugPayload(Self.debugPretendHealthExamJSON)
            return (.healthExamReport(payload), try prettyJSONString(from: payload))

        case .medicalReport, .auto:
            let payload: [MedicalReportRecognitionDraft] = try decodeDebugPayload(Self.debugPretendMedicalReportJSON)
            return (.medicalReport(payload), try prettyJSONString(from: payload))

        case .prescription:
            let payload: PrescriptionRecognitionDraft = try decodeDebugPayload(Self.debugPretendPrescriptionJSON)
            return (.prescription(payload), try prettyJSONString(from: payload))

        case .medicationPlan:
            let payload: [MedicationPlanRecognitionDraft] = try decodeDebugPayload(Self.debugPretendMedicationPlanJSON)
            return (.medicationPlan(payload), try prettyJSONString(from: payload))

        case .medicineBox:
            let payload: [MedicineBoxRecognitionDraft] = try decodeDebugPayload(Self.debugPretendMedicineBoxJSON)
            return (.medicineBoxes(payload), try prettyJSONString(from: payload))
        }
    }

    func makeDebugPretendCaseOutput(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        selectedKind: MedicalDocumentKind
    ) throws -> MedicalDocumentTypedExtractionOutput {
        try makeDebugPretendOutput(memberID: memberID, files: files, selectedKind: selectedKind)
    }

    func decodeDebugPayload<T: Decodable>(_ json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw ExtractionError.invalidDebugPayload
        }
        return try JSONDecoder.default.decode(T.self, from: data)
    }

    static func debugResolvedKind(for selectedKind: MedicalDocumentKind) -> MedicalDocumentKind {
        selectedKind == .auto ? .medicalReport : selectedKind
    }

    func prettyJSONString<T: Encodable>(from value: T) throws -> String {
        let text = try JSONPayloadFormatting.prettyString(from: value)
        guard text != "<empty>", text.hasPrefix("<非 UTF-8") == false else {
            throw ExtractionError.invalidDebugPayload
        }
        return text
    }

    static let debugPretendHealthExamJSON = """
    {
        "institutionName": "苏州工业园区星塘医院体检中心",
        "reportNo": "HE-DEBUG-20260520",
        "examDate": "2026-05-20",
        "examType": "年度健康体检",
        "summary": "本次体检提示低密度脂蛋白胆固醇轻度升高，肝肾功能未见明显异常。建议清淡饮食、规律运动，3个月后复查血脂。",
        "items": [
            {
                "category": "血脂",
                "subCategory": "生化",
                "itemName": "低密度脂蛋白胆固醇",
                "itemCode": "LDL-C",
                "resultValue": "3.51",
                "unit": "mmol/L",
                "referenceRange": "0.00-3.37",
                "flag": "↑",
                "resultAt": "2026-05-20",
                "sortOrder": "1"
            },
            {
                "category": "肝功能",
                "subCategory": "生化",
                "itemName": "丙氨酸氨基转移酶",
                "itemCode": "ALT",
                "resultValue": "24",
                "unit": "U/L",
                "referenceRange": "9-50",
                "flag": "正常",
                "resultAt": "2026-05-20",
                "sortOrder": "2"
            },
            {
                "category": "肾功能",
                "subCategory": "生化",
                "itemName": "肌酐",
                "itemCode": "CREA",
                "resultValue": "72",
                "unit": "umol/L",
                "referenceRange": "57-97",
                "flag": "正常",
                "resultAt": "2026-05-20",
                "sortOrder": "3"
            }
        ]
    }
    """

    static let debugPretendMedicalReportJSON = """
    [
        {
            "category": "imaging",
            "title": "颈椎CT平扫报告",
            "hospital": "苏州工业园区星塘医院",
            "doctor": "王医生",
            "content": "颈椎生理曲度变直，C4/5、C5/6椎间盘轻度后突，相邻硬膜囊稍受压。椎旁软组织未见明显肿胀。",
            "date": "2026-05-20",
            "details": [
                {
                    "category": "放射科",
                    "subCategory": "CT",
                    "itemName": "颈椎CT平扫",
                    "resultValue": "C4/5、C5/6椎间盘轻度后突",
                    "bodyPart": "颈椎",
                    "diagnosis": "颈椎退变；C4/5、C5/6椎间盘轻度突出",
                    "sortOrder": "1"
                }
            ]
        },
        {
            "category": "lab",
            "title": "血常规检验报告",
            "hospital": "苏州工业园区星塘医院",
            "doctor": "李医生",
            "content": "白细胞、红细胞、血红蛋白及血小板计数均在参考范围内。",
            "date": "2026-05-20",
            "details": [
                {
                    "category": "血常规",
                    "itemName": "白细胞计数",
                    "itemCode": "WBC",
                    "resultValue": "6.2",
                    "unit": "10^9/L",
                    "referenceRange": "3.5-9.5",
                    "flag": "正常",
                    "sortOrder": "1"
                },
                {
                    "category": "血常规",
                    "itemName": "血红蛋白",
                    "itemCode": "HGB",
                    "resultValue": "145",
                    "unit": "g/L",
                    "referenceRange": "130-175",
                    "flag": "正常",
                    "sortOrder": "2"
                }
            ]
        }
    ]
    """

    static let debugPretendPrescriptionJSON = """
    {
        "medicalCase": null,
        "prescriberName": "周医生",
        "institutionName": "苏州大学附属第四医院",
        "prescribedAt": "2026-05-20",
        "diagnosis": "前庭性眩晕",
        "prescriptionNo": "RX-DEBUG-0520",
        "status": "active",
        "extra": {
            "source": "debug_pretend_prescription"
        },
        "medicationPlans": [
            {
                "medicineName": "甲磺酸倍他司汀片",
                "medicineType": "western",
                "brandName": "敏使朗",
                "dosageForm": "片剂",
                "strength": "6mg",
                "dosePerTime": "6mg",
                "doseValue": "1",
                "doseUnit": "片",
                "frequencyType": "daily",
                "frequencyText": "每日3次",
                "startDate": "2026-05-20",
                "endDate": "2026-06-03",
                "instructions": "饭后口服",
                "reminderEnabled": true,
                "reminderTimes": [{"time": "08:00"}, {"time": "13:00"}, {"time": "19:00"}],
                "status": "active",
                "sortOrder": "1"
            },
            {
                "medicineName": "盐酸氟桂利嗪胶囊",
                "medicineType": "western",
                "dosageForm": "胶囊",
                "strength": "5mg",
                "dosePerTime": "5mg",
                "doseValue": "1",
                "doseUnit": "粒",
                "frequencyType": "daily",
                "frequencyText": "每晚1次",
                "startDate": "2026-05-20",
                "endDate": "2026-06-03",
                "instructions": "睡前服用，如嗜睡明显请咨询医生",
                "reminderEnabled": true,
                "reminderTimes": [{"time": "21:30"}],
                "status": "active",
                "sortOrder": "2"
            }
        ]
    }
    """

    static let debugPretendMedicationPlanJSON = """
    [
        {
            "medicineName": "普拉洛芬滴眼液",
            "medicineType": "western",
            "brandName": "普南扑灵",
            "dosageForm": "滴眼液",
            "strength": "5ml:5mg",
            "dosePerTime": "1滴",
            "doseValue": "1",
            "doseUnit": "滴",
            "frequencyType": "daily",
            "frequencyText": "每日4次",
            "startDate": "2026-05-20",
            "endDate": "2026-05-27",
            "instructions": "滴入患眼，避免瓶口接触眼部",
            "reminderEnabled": true,
            "reminderTimes": [{"time": "08:00"}, {"time": "12:00"}, {"time": "18:00"}, {"time": "22:00"}],
            "status": "active",
            "sortOrder": "1"
        },
        {
            "medicineName": "盐酸氮卓斯汀滴眼液",
            "medicineType": "western",
            "brandName": "爱赛平",
            "dosageForm": "滴眼液",
            "strength": "6ml:3mg",
            "dosePerTime": "1滴",
            "doseValue": "1",
            "doseUnit": "滴",
            "frequencyType": "daily",
            "frequencyText": "每日2次",
            "startDate": "2026-05-20",
            "endDate": "2026-06-03",
            "instructions": "开启瓶封后使用不超过四周",
            "reminderEnabled": true,
            "reminderTimes": [{"time": "09:00"}, {"time": "21:00"}],
            "status": "active",
            "sortOrder": "2"
        }
    ]
    """

    static let debugPretendMedicineBoxJSON = """
    [
        {
            "medicineName": "布洛芬缓释胶囊",
            "medicineType": "western",
            "brandName": "芬必得",
            "dosageForm": "胶囊",
            "strength": "0.3g",
            "doseUnit": "粒",
            "totalQuantity": "20",
            "expireDate": "2028-06-30",
            "notes": "用于缓解轻至中度疼痛，胃部不适或过敏史需谨慎。",
            "sortOrder": "1"
        },
        {
            "medicineName": "蒙脱石散",
            "medicineType": "western",
            "brandName": "思密达",
            "dosageForm": "散剂",
            "strength": "3g/袋",
            "doseUnit": "袋",
            "totalQuantity": "10",
            "expireDate": "2027-12-31",
            "notes": "冲服，需与其他药物间隔使用。",
            "sortOrder": "2"
        }
    ]
    """

    static let debugPretendCaseJSON = """
    {
        "title": "就诊病例",
        "summary": "患者赵道凯，2025年8月2日因反复头晕2月于苏州大学附属第四医院神经内科就诊，诊断为前庭性眩晕，予甲磺酸倍他司汀片治疗；2025年6月苏州工业园区星塘医院CT提示C4/5、C5/6椎间盘轻微突出等；2026年2月胃镜诊断慢性非萎缩性胃炎伴胆汁反流；2025年7月消化科就诊提示肠功能紊乱，行血细胞分析、粪便检验未见明显异常；2025年12月因口腔黏膜溃疡行生化、肾功能检验，低密度脂蛋白胆固醇3.511mmol/L略高；2026年4月皮肤科诊断结膜炎，予普拉洛芬滴眼液、盐酸氮卓斯汀滴眼液治疗。",
        "diagnosis": "前庭性眩晕；慢性非萎缩性胃炎伴胆汁反流；肠功能紊乱；口腔黏膜溃疡；结膜炎",
        "hospitalName": "苏州大学附属第四医院（苏州市独墅湖医院）；苏州工业园区星塘医院",
        "ageAtVisit": "26",
        "occurredAt": "2025-08-02",
        "symptom": {
            "name": "头晕",
            "severity": "medium",
            "durationValue": "2",
            "durationUnit": "月",
            "bodyPart": "头部",
            "notes": "伴视物旋转，体位改变症状明显，伴恶心呕吐，每次持续2小时后自行缓解，无肢体活动障碍，无行走不稳"
        },
        "visit": {
            "visitType": "门诊",
            "visitedAt": "2025-08-02",
            "department": "神经内科门诊",
            "doctorName": "",
            "visitNo": "0000349056"
        },
        "prescriptions": [
            {
                "prescriberName": "",
                "institutionName": "苏州大学附属第四医院",
                "prescribedAt": "2025-08-02",
                "diagnosis": "前庭性眩晕",
                "medicationPlans": [
                    {
                        "medicineName": "甲磺酸倍他司汀片（敏使朗）",
                        "strength": "6mg",
                        "dosePerTime": "6mg",
                        "frequencyText": "每天3次"
                    }
                ]
            },
            {
                "prescriberName": "",
                "institutionName": "苏州大学附属第四医院",
                "prescribedAt": "2026-04-20",
                "diagnosis": "结膜炎",
                "medicationPlans": [
                    {
                        "medicineName": "普拉洛芬滴眼液（普南扑灵）",
                        "strength": "5ml:5mg",
                        "dosePerTime": "1滴",
                        "frequencyText": "每天4次",
                        "expireDate": "2028-09-01"
                    },
                    {
                        "medicineName": "盐酸氮卓斯汀滴眼液（爱赛平）",
                        "strength": "6ml:3mg（0.05%）",
                        "dosePerTime": "1滴",
                        "frequencyText": "每天2次",
                        "instructions": "开启瓶封后，使用不可超过四周"
                    }
                ]
            }
        ],
        "examinationReports": [
            {
                "category": "imaging",
                "title": "放射科诊断报告书",
                "hospital": "苏州工业园区星塘医院",
                "doctor": "仿德话",
                "content": "头颅CT平扫示脑实质未见明显异常密度影，各脑室形态大小正常，脑沟、裂池未见明显异常，中线结构居中。小脑及脑干未见异常密度影。鼻咽顶后壁软组织增；颈椎序列整齐，生理曲度平直，椎体缘可见骨质增生，椎小关节突对称，C4/5、C5/6椎间盘稍向后突出，相邻硬膜囊稍受压：骨性椎管无明显狭窄，椎旁软组织无明显肿胀。两侧颈部、颌下区多发小淋巴结。所示右侧声带相对稍厚。影像诊断：1.头颅CT平扫未见明显异常，必要时MRI检查。鼻咽顶后壁软组织增厚，请结合专科检查。2.C4/5、C5/6椎间盘轻微突出：颈椎失稳：两侧颈部、颌下区多发小淋巴结。所示右侧声带相对稍厚。",
                "date": "2025-06-04",
                "details": [
                    {
                        "category": "放射科",
                        "subCategory": "CT",
                        "itemName": "颈椎椎间盘平扫，头颅平扫",
                        "resultValue": "1.头颅CT平扫未见明显异常，必要时MRI检查。鼻咽顶后壁软组织增厚，请结合专科检查。2.C4/5、C5/6椎间盘轻微突出：颈椎失稳：两侧颈部、颌下区多发小淋巴结。所示右侧声带相对稍厚。",
                        "bodyPart": "头颈部",
                        "diagnosis": "头颅CT平扫未见明显异常；C4/5、C5/6椎间盘轻微突出；颈椎失稳；两侧颈部、颌下区多发小淋巴结；右侧声带相对稍厚"
                    }
                ]
            },
            {
                "category": "imaging",
                "title": "胃镜诊断报告单",
                "hospital": "苏州大学附属第四医院",
                "doctor": "欧啡",
                "content": "内镜所见：食管：通过顺利，黏膜大致正常；贲门：开合佳通畅；胃底：黏膜正常；胃体：见胆汁残留；胃角：光整；胃窦：黏膜红白相间，以红为主；幽门：圆，开放好；十二指肠球部及所见降部：未见明显异常。诊断：慢性非萎缩性胃炎伴胆汁反流",
                "date": "2026-02-10",
                "details": [
                    {
                        "category": "消化内科",
                        "subCategory": "胃镜",
                        "itemName": "无痛电子胃镜",
                        "resultValue": "慢性非萎缩性胃炎伴胆汁反流",
                        "bodyPart": "上消化道",
                        "diagnosis": "慢性非萎缩性胃炎伴胆汁反流"
                    }
                ]
            },
            {
                "category": "laboratory",
                "title": "检验报告单（血细胞分析+CRP）",
                "hospital": "苏州大学附属第四医院",
                "doctor": "冯玎琦",
                "content": "临床印象：肠功能紊乱；送检项目：血细胞分析+CRP；结果无明显异常",
                "date": "2025-07-05",
                "details": [
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "白细胞计数",
                        "resultValue": "5.56",
                        "unit": "10^9/L",
                        "referenceRange": "3.5--9.5"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "中性粒细胞计数",
                        "resultValue": "3.24",
                        "unit": "10^9/L",
                        "referenceRange": "1.8--6.3"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "淋巴细胞计数",
                        "resultValue": "1.95",
                        "unit": "10^9/L",
                        "referenceRange": "1.1--3.2"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "单核细胞计数",
                        "resultValue": "0.34",
                        "unit": "10^9/L",
                        "referenceRange": "0.1--0.6"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "嗜酸性粒细胞计数",
                        "resultValue": "0.03",
                        "unit": "10^9/L",
                        "referenceRange": "0.02--0.52"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "嗜碱性粒细胞计数",
                        "resultValue": "0.00",
                        "unit": "10^9/L",
                        "referenceRange": "0--0.06"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "中性粒细胞百分比",
                        "resultValue": "58.2",
                        "unit": "%",
                        "referenceRange": "40--75"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "淋巴细胞百分比",
                        "resultValue": "35.1",
                        "unit": "%",
                        "referenceRange": "20--50"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "单核细胞百分比",
                        "resultValue": "6.1",
                        "unit": "%",
                        "referenceRange": "3--10"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "嗜酸性粒细胞百分比",
                        "resultValue": "0.6",
                        "unit": "%",
                        "referenceRange": "0.4--8"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "嗜碱性粒细胞百分比",
                        "resultValue": "0.0",
                        "unit": "%",
                        "referenceRange": "0--1"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "红细胞计数",
                        "resultValue": "4.74",
                        "unit": "10^12/L",
                        "referenceRange": "4.3--5.8"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "血红蛋白",
                        "resultValue": "141",
                        "unit": "g/L",
                        "referenceRange": "130--175"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "红细胞比积",
                        "resultValue": "41.30",
                        "unit": "%",
                        "referenceRange": "40--50"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "红细胞平均体积",
                        "resultValue": "87.2",
                        "unit": "fL",
                        "referenceRange": "82--100"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "红细胞平均血红蛋白量",
                        "resultValue": "29.8",
                        "unit": "pg",
                        "referenceRange": "27--34"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "红细胞平均血红蛋白浓度",
                        "resultValue": "341",
                        "unit": "g/L",
                        "referenceRange": "316--354"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "红细胞分布宽度",
                        "resultValue": "13.2",
                        "unit": "%",
                        "referenceRange": "0.0--15.0"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "血小板计数",
                        "resultValue": "270",
                        "unit": "10^9/L",
                        "referenceRange": "125--350"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "血小板比积",
                        "resultValue": "0.240",
                        "unit": "%",
                        "referenceRange": "0.11--0.28"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "平均血小板体积",
                        "resultValue": "8.9",
                        "unit": "fL",
                        "referenceRange": "6.5--12"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血细胞分析",
                        "itemName": "血小板分布宽度",
                        "resultValue": "16.0",
                        "unit": "fL",
                        "referenceRange": "≤17"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "CRP",
                        "itemName": "超敏C反应蛋白",
                        "resultValue": "0.93",
                        "unit": "mg/L",
                        "referenceRange": "0--6"
                    }
                ]
            },
            {
                "category": "laboratory",
                "title": "检验报告单（粪便检验+隐血）",
                "hospital": "苏州大学附属第四医院",
                "doctor": "丁海浜",
                "content": "临床印象：肠功能紊乱；送检项目：粪便检验+隐血；结果无明显异常",
                "date": "2025-07-05",
                "details": [
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "粪便颜色",
                        "resultValue": "黄色"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "粪便性状",
                        "resultValue": "软便"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "粪白细胞",
                        "resultValue": "未见",
                        "unit": "个/HP",
                        "referenceRange": "0--1"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "粪红细胞",
                        "resultValue": "未见",
                        "unit": "个/HP",
                        "referenceRange": "未见"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "吞噬细胞",
                        "resultValue": "未见",
                        "unit": "个/HP",
                        "referenceRange": "未见"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "淀粉颗粒",
                        "resultValue": "未见",
                        "referenceRange": "未见或偶见"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "脂肪球",
                        "resultValue": "未见",
                        "referenceRange": "未见或偶见"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "花粉",
                        "resultValue": "未见"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "寄生虫",
                        "resultValue": "未见",
                        "referenceRange": "未见"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "虫卵",
                        "resultValue": "未见",
                        "referenceRange": "未见"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "夏科莱登结晶",
                        "resultValue": "未见",
                        "referenceRange": "未见"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "孢子",
                        "resultValue": "未见",
                        "referenceRange": "未见"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "粪便检验",
                        "itemName": "菌丝",
                        "resultValue": "未见",
                        "referenceRange": "未见"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "隐血试验",
                        "itemName": "隐血",
                        "resultValue": "阴性",
                        "referenceRange": "阴性",
                        "flag": "阴性"
                    }
                ]
            },
            {
                "category": "laboratory",
                "title": "检验报告单（生化检验、肾功能检验）",
                "hospital": "苏州大学附属第四医院",
                "doctor": "王斐",
                "content": "临床印象：口腔黏膜溃疡；送检项目：生化检验，肾功能检验；低密度脂蛋白胆固醇3.511mmol/L略高于适宜范围，其余无明显异常",
                "date": "2025-12-28",
                "details": [
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "间接胆红素",
                        "resultValue": "13.5",
                        "unit": "umol/L",
                        "referenceRange": "≤26"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "直接胆红素",
                        "resultValue": "4.2",
                        "unit": "umol/L",
                        "referenceRange": "≤8"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "间接胆红素",
                        "resultValue": "9.3",
                        "unit": "umol/L"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "天门冬氨酸氨基转移酶",
                        "resultValue": "13.5",
                        "unit": "U/L"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "丙氨酸氨基转移酶",
                        "resultValue": "14.6",
                        "unit": "U/L"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "总蛋白",
                        "resultValue": "77.0",
                        "unit": "g/L"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "白蛋白",
                        "resultValue": "47.4",
                        "unit": "g/L"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "球蛋白",
                        "resultValue": "29.6",
                        "unit": "g/L"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "白蛋白/球蛋白",
                        "resultValue": "1.6"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "γ-谷氨酰转肽酶",
                        "resultValue": "19.9",
                        "unit": "U/L"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "碱性磷酸酶",
                        "resultValue": "75.9",
                        "unit": "U/L"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "乳酸脱氢酶",
                        "resultValue": "168.0",
                        "unit": "U/L",
                        "referenceRange": "120--250"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "α-羟丁酸脱氧酶",
                        "resultValue": "140.4",
                        "unit": "U/L",
                        "referenceRange": "72--182"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "生化检验",
                        "itemName": "胆碱酯酶",
                        "resultValue": "11124",
                        "unit": "U/L"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血脂检验",
                        "itemName": "甘油三酯",
                        "resultValue": "0.70",
                        "unit": "mmol/L",
                        "referenceRange": "≤1.70"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血脂检验",
                        "itemName": "总胆固醇",
                        "resultValue": "5.07",
                        "unit": "mmol/L",
                        "referenceRange": "＜5.18"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血脂检验",
                        "itemName": "高密度脂蛋白胆固醇",
                        "resultValue": "1.51",
                        "unit": "mmol/L",
                        "referenceRange": ">1.04"
                    },
                    {
                        "category": "检验科",
                        "subCategory": "血脂检验",
                        "itemName": "低密度脂蛋白胆固醇",
                        "resultValue": "3.511",
                        "unit": "mmol/L",
                        "referenceRange": "＜3.40",
                        "flag": "H"
                    }
                ]
            }
        ]
    }
    """
}
#endif
