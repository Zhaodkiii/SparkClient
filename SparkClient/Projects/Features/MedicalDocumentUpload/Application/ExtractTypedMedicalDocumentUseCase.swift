import Foundation

/// 医疗单据【类型化】结构化提取 用例
/// 职责：统一入口 → 合并OCR文本 → 识别单据类型 → 提取结构化字段（诊断、药品、日期等）
/// 属于业务逻辑层，不关心具体实现，只对外提供稳定接口
struct ExtractTypedMedicalDocumentUseCase: Sendable {
    /// 医疗单据类型化提取器（具体实现的协议接口）
    let extractor: any TypedMedicalDocumentExtracting

    func recognizeOCRFiles(
        files: [MedicalUploadLocalFile],
        reRecognizeAll: Bool = true,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> [MedicalUploadLocalFile] {
        try cancellationToken?.checkCancellation()
        return try await extractor.recognizeOCRFiles(
            files: files,
            reRecognizeAll: reRecognizeAll,
            cancellationToken: cancellationToken
        )
    }

    /// 合并多个上传文件的 OCR 识别文本
    /// - Parameters:
    ///   - files: 本地医疗单据文件列表
    ///   - reRecognizeAll: 是否全部重新识别；为 `false` 时已有 `ocrText` 的文件将跳过 OCR
    ///   - cancellationToken: 取消令牌（中途可终止任务）
    /// - Returns: 合并后的完整OCR文本
    func mergeOCRText(
        files: [MedicalUploadLocalFile],
        reRecognizeAll: Bool = true,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> String {
        try cancellationToken?.checkCancellation()
        return try await extractor.mergeOCRText(
            files: files,
            reRecognizeAll: reRecognizeAll,
            cancellationToken: cancellationToken
        )
    }

    /// 根据OCR文本，解析/确定医疗单据的具体类型
    /// 例如：判断是 病历 / 处方 / 检查报告 / 出院小结 等
    /// - Parameters:
    ///   - selectedKind: 用户手动选择的单据大类
    ///   - mergedOCRText: 合并后的OCR文本
    ///   - cancellationToken: 取消令牌
    /// - Returns: 单据类型识别结果
    func resolveType(
        selectedKind: MedicalDocumentKind,
        mergedOCRText: String,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> MedicalDocumentTypeResolution {
        try cancellationToken?.checkCancellation()
        return try await extractor.resolveType(
            selectedKind: selectedKind,
            mergedOCRText: mergedOCRText,
            cancellationToken: cancellationToken
        )
    }

    /// 执行【结构化提取】
    /// 从OCR文本中提取关键字段：诊断、药品、时间、医院、科室等
    /// - Parameters:
    ///   - memberID: 用户ID/会员ID
    ///   - files: 医疗文件列表
    ///   - mergedOCRText: OCR合并文本
    ///   - resolution: 单据类型识别结果
    ///   - preferredModelName: 优先使用的AI模型
    ///   - retryFeedback: 上次结构化抽取失败反馈，继续识别时追加到 Prompt
    ///   - cancellationToken: 取消令牌
    /// - Returns: 结构化提取输出（格式化好的医疗数据）
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
        return try await extractor.extractStructured(
            memberID: memberID,
            files: files,
            mergedOCRText: mergedOCRText,
            resolution: resolution,
            preferredModelName: preferredModelName,
            retryFeedback: retryFeedback,
            cancellationToken: cancellationToken
        )
    }

    /// 用例【完整执行入口】
    /// 一键执行：OCR → 类型识别 → 结构化提取 全流程
    /// - Parameters:
    ///   - memberID: 用户ID
    ///   - files: 上传的医疗单据文件
    ///   - selectedKind: 用户选择的单据类型
    ///   - cancellationToken: 取消令牌
    /// - Returns: 最终结构化提取结果
    func execute(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        selectedKind: MedicalDocumentKind,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> MedicalDocumentTypedExtractionOutput {
        try cancellationToken?.checkCancellation()
        return try await extractor.extract(
            memberID: memberID,
            files: files,
            selectedKind: selectedKind,
            cancellationToken: cancellationToken
        )
    }
}
