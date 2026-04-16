// 导入Foundation框架，提供基础数据类型、文件、网络、异步等核心功能
import Foundation

/// 默认实现的 医疗文档类型化抽取器
/// 核心职责：对上传的医疗文件做 OCR 识别 → 文档类型判定 → AI 抽取结构化数据 → 组装标准输出
/// 遵循 TypedMedicalDocumentExtracting 协议 + Sendable 保证跨异步/线程安全
struct DefaultTypedMedicalDocumentExtractor: TypedMedicalDocumentExtracting, Sendable {
    // MARK: - 依赖注入组件（所有外部能力都通过初始化传入，解耦、可测试）
    /// OCR 编排与拼接模块（图片/文档识别 + merged text）
    let ocrBuilder: any MedicalDocumentOCRBuilding
    /// 文档类型解析器：根据 OCR 文本判断当前是哪种医疗文档（病例/体检报告/处方等）
    let typeResolver: any MedicalDocumentTypeResolving
    /// 结构化抽取模块：根据类型调用 AI 并返回 typed + JSON
    let structuredExtractor: any MedicalDocumentStructuredExtracting
    /// 日志器：打印 Info/Debug/Warning 日志，方便排查问题
    let logger: Logger

    // MARK: - 初始化器（依赖注入入口）
    /// 初始化医疗文档类型化抽取器
    /// - 所有核心能力通过外部传入，遵循依赖倒置原则，便于单元测试和替换实现
    init(
        ocrBuilder: any MedicalDocumentOCRBuilding,
        typeResolver: any MedicalDocumentTypeResolving,
        structuredExtractor: any MedicalDocumentStructuredExtracting,
        logger: Logger = ConsoleLogger()
    ) {
        // 赋值所有依赖
        self.ocrBuilder = ocrBuilder
        self.typeResolver = typeResolver
        self.structuredExtractor = structuredExtractor
        self.logger = logger
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
        let mergedOCR = try await ocrBuilder.buildMergedOCRText(files: files)
        
        // 2. 根据用户选择类型 + OCR文本，最终确定文档类型（病例/体检/处方等）
        let resolution = try await typeResolver.resolve(selectedKind: selectedKind, mergedOCRText: mergedOCR)
        // 解析出最终判定的文档类型
        let kind = resolution.kind
        
        // 3. 调用结构化抽取模块，得到类型化结果 + 标准JSON
        let extraction = try await structuredExtractor.extract(kind: kind, mergedOCRText: mergedOCR)
        let extractedJSON = extraction.extractedJSON
        
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
            typedResult: extraction.typedResult,
            extractedJSON: extractedJSON,
            payloadPreview: preview
        )
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
    [
        {
            "category": "影像学检查",
            "title": "胃镜诊断报告单",
            "hospital": "苏州大学附属第四医院 苏州市独墅湖医院",
            "doctor": "欧啡",
            "content": "内镜所见：食管：通过顺利，黏膜大致正常；贲门：开合伟通畅；胃底：黏膜正常；胃体：见胆汁残留；胃角：光整；胃窦：黏膜红白相问，以红为主；幽门：圆，开放好；十二指肠球部及所见降部：未见明显异常。诊断：慢性非萎缩性胃炎伴胆汁反流",
            "date": "2026-02-10",
            "details": [
                {
                    "category": "imaging",
                    "subCategory": "胃镜检查",
                    "itemName": "无痛电子胃镜（不含麻醉费）",
                    "modality": "无痛电子胃镜",
                    "bodyPart": "食管、贲门、胃底、胃体、胃角、胃窦、十二指肠球部、十二指肠降部",
                    "diagnosis": "慢性非萎缩性胃炎伴胆汁反流",
                    "sortOrder": 1
                }
            ]
        }
    ]
    """
}
#endif
