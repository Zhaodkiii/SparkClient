import Foundation

/// 医疗上传流水线使用的 Prompt 拼装协议：`PromptLocalizer` + 文书类型 → 发给模型的完整 user 文案。
protocol MedicalPromptBuilding: Sendable {
    /// 根据 OCR 全文生成分类提示（输出 kind / confidence / reason 的 JSON）。
    func typeRecognitionPrompt(ocrText: String) -> String
    /// 按用户选定或解析得到的 `MedicalDocumentKind` 选择抽取模板（结构化 JSON 指令）。
    func extractionPrompt(for input: MedicalPromptInput) -> String
}

/// 构造 `MedicalPromptBuilding.extractionPrompt(for:)` 的输入：文书类型与合并后的 OCR 文本。
struct MedicalPromptInput: Sendable {
    let kind: MedicalDocumentKind
    let mergedOCRText: String
}

/// 默认实现：委托 `PromptLocalizer` 读取 `Prompts.strings`（按当前 `Locale`），保证类型识别与各类抽取模板与用户语言一致。
struct MedicalPromptFactory: MedicalPromptBuilding {
    private let localizer: PromptLocalizer

    init(localizer: PromptLocalizer = PromptLocalizer()) {
        self.localizer = localizer
    }

    func typeRecognitionPrompt(ocrText: String) -> String {
        localizer.medicalDocumentTypeRecognitionPrompt(ocrText: ocrText)
    }

    func extractionPrompt(for input: MedicalPromptInput) -> String {
        switch input.kind {
        case .auto:
            // 未指定类型：使用通用医疗文档 schema（含 rawType、items 等扩展字段）。
            return localizer.medicalDocumentExtractionPrompt(ocrText: input.mergedOCRText)
        case .caseDocument:
            return localizer.medicalCaseExtractionPrompt(ocrText: input.mergedOCRText)
        case .healthExamReport:
            return localizer.healthExamExtractionPrompt(ocrText: input.mergedOCRText)
        case .medicalReport:
            return localizer.medicalReportExtractionPrompt(ocrText: input.mergedOCRText)
        case .prescription:
            return localizer.prescriptionExtractionPrompt(ocrText: input.mergedOCRText)
        case .medicationPlan:
            return localizer.medicationExtractionPrompt(ocrText: input.mergedOCRText)
        case .medicineBox:
            return localizer.medicineBoxExtractionPrompt(ocrText: input.mergedOCRText)
        }
    }
}
