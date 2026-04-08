import Foundation

/// AI 能力场景枚举，用于配置分流与模型选择。
enum AIScenario: String, Codable, CaseIterable, Sendable {
    /// 通用对话场景，通常用于主聊天能力。
    case chat
    /// 医疗文档结构化抽取场景（如从报告中提取字段化信息）。
    case medicalStructuredExtraction = "medical_structured_extraction"
    /// 医疗文档类型识别场景（自动识别：病例/体检/医疗报告/处方/用药）。
    case medicalDocumentTypeRecognition = "medical_document_type_recognition"
    /// 病例结构化抽取场景。
    case medicalCaseExtraction = "medical_case_extraction"
    /// 体检报告结构化抽取场景。
    case healthExamExtraction = "health_exam_extraction"
    /// 医疗报告结构化抽取场景。
    case medicalReportExtraction = "medical_report_extraction"
    /// 处方结构化抽取场景。
    case prescriptionExtraction = "prescription_extraction"
    /// 用药结构化抽取场景。
    case medicationExtraction = "medication_extraction"
    /// 文本优化场景（润色、改写、纠错、摘要等）。
    case optimizationText = "optimization_text"
    /// 视觉内容优化场景（图像相关理解/优化链路）。
    case optimizationVisual = "optimization_visual"
    /// 上下文折叠场景（长上下文压缩、重组与检索前处理）。
    case contextFolding = "context_folding"
    /// 路由场景（用于在多模型/多策略之间进行请求分流决策）。
    case router
    /// 模型配置场景（用于拉取、解析或管理模型元配置）。
    case modelConfig = "model_config"
    /// 报告解读场景（对医疗报告进行解释、说明或风险提示）。
    case reportInterpretation = "report_interpretation"
}
