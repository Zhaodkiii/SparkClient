import Foundation

/// AI 能力场景枚举，用于配置分流与模型选择。
enum AIScenario: String, Codable, CaseIterable, Sendable {
    /// 通用对话场景，通常用于主聊天能力。
    case chat
    /// 向量模型场景（知识检索/索引等向量化链路）。
    case embedding
    /// 语音模型场景（TTS/语音合成链路）。
    case voice
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
    /// 用药结构化抽取场景（服药计划等）。
    case medicationExtraction = "medication_extraction"
    /// 药品结构化抽取场景（药盒/药箱标签等）。
    case medicineBoxExtraction = "medicine_box_extraction"
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
    /// 营养摄入结构化抽取场景（食物描述/自然语言 → 营养草稿 JSON）。
    case nutritionIntakeExtraction = "nutrition_intake_extraction"
    /// 体检计划生成场景。
    case medicalExamPlanGeneration = "medical_exam_plan_generation"
}

extension AIScenario {
    var localizedTitle: String {
        switch self {
        case .chat:
            return L10n.text("ai_settings.scenario.chat")
        case .embedding:
            return L10n.text("ai_settings.scenario.embedding")
        case .voice:
            return L10n.text("ai_settings.scenario.voice")
        case .medicalStructuredExtraction:
            return L10n.text("ai_settings.scenario.medical_structured_extraction")
        case .medicalDocumentTypeRecognition:
            return L10n.text("ai_settings.scenario.medical_document_type_recognition")
        case .medicalCaseExtraction:
            return L10n.text("ai_settings.scenario.medical_case_extraction")
        case .healthExamExtraction:
            return L10n.text("ai_settings.scenario.health_exam_extraction")
        case .medicalReportExtraction:
            return L10n.text("ai_settings.scenario.medical_report_extraction")
        case .prescriptionExtraction:
            return L10n.text("ai_settings.scenario.prescription_extraction")
        case .medicationExtraction:
            return L10n.text("ai_settings.scenario.medication_extraction")
        case .medicineBoxExtraction:
            return L10n.text("ai_settings.scenario.medicine_box_extraction")
        case .optimizationText:
            return L10n.text("ai_settings.scenario.optimization_text")
        case .optimizationVisual:
            return L10n.text("ai_settings.scenario.optimization_visual")
        case .contextFolding:
            return L10n.text("ai_settings.scenario.context_folding")
        case .router:
            return L10n.text("ai_settings.scenario.router")
        case .modelConfig:
            return L10n.text("ai_settings.scenario.model_config")
        case .reportInterpretation:
            return L10n.text("ai_settings.scenario.report_interpretation")
        case .nutritionIntakeExtraction:
            return L10n.text("ai_settings.scenario.nutrition_intake_extraction")
        case .medicalExamPlanGeneration:
            return L10n.text("ai_settings.scenario.medical_exam_plan_generation")
        }
    }

    var introIconSystemName: String {
        switch self {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .embedding:
            return "point.3.connected.trianglepath.dotted"
        case .voice:
            return "waveform"
        case .medicalStructuredExtraction:
            return "cross.case"
        case .medicalDocumentTypeRecognition:
            return "doc.text.viewfinder"
        case .medicalCaseExtraction:
            return "cross.vial"
        case .healthExamExtraction:
            return "heart.text.square"
        case .medicalReportExtraction:
            return "doc.text.magnifyingglass"
        case .prescriptionExtraction:
            return "pills"
        case .medicationExtraction:
            return "cross.case.circle"
        case .medicineBoxExtraction:
            return "shippingbox.fill"
        case .optimizationText:
            return "paintbrush.pointed"
        case .optimizationVisual:
            return "paintbrush"
        case .contextFolding:
            return "rectangle.compress.vertical"
        case .router:
            return "arrow.triangle.branch"
        case .modelConfig:
            return "slider.horizontal.3"
        case .reportInterpretation:
            return "stethoscope"
        case .nutritionIntakeExtraction:
            return "fork.knife"
        case .medicalExamPlanGeneration:
            return "list.clipboard"
        }
    }

    var localizedIntro: String {
        switch self {
        case .chat:
            return L10n.text("ai_settings.prefs.explain.chat")
        case .embedding:
            return L10n.text("ai_settings.prefs.explain.embedding")
        case .voice:
            return L10n.text("ai_settings.prefs.explain.voice")
        case .medicalStructuredExtraction:
            return L10n.text("ai_settings.prefs.explain.medical_structured_extraction")
        case .medicalDocumentTypeRecognition:
            return L10n.text("ai_settings.prefs.explain.medical_document_type_recognition")
        case .medicalCaseExtraction:
            return L10n.text("ai_settings.prefs.explain.medical_case_extraction")
        case .healthExamExtraction:
            return L10n.text("ai_settings.prefs.explain.health_exam_extraction")
        case .medicalReportExtraction:
            return L10n.text("ai_settings.prefs.explain.medical_report_extraction")
        case .prescriptionExtraction:
            return L10n.text("ai_settings.prefs.explain.prescription_extraction")
        case .medicationExtraction:
            return L10n.text("ai_settings.prefs.explain.medication_extraction")
        case .medicineBoxExtraction:
            return L10n.text("ai_settings.prefs.explain.medicine_box_extraction")
        case .optimizationText:
            return L10n.text("ai_settings.prefs.explain.optimization_text")
        case .optimizationVisual:
            return L10n.text("ai_settings.prefs.explain.optimization_visual")
        case .contextFolding:
            return L10n.text("ai_settings.prefs.explain.context_folding")
        case .router:
            return L10n.text("ai_settings.prefs.explain.router")
        case .modelConfig:
            return L10n.text("ai_settings.prefs.explain.model_config")
        case .reportInterpretation:
            return L10n.text("ai_settings.prefs.explain.report_interpretation")
        case .nutritionIntakeExtraction:
            return L10n.text("ai_settings.prefs.explain.nutrition_intake_extraction")
        case .medicalExamPlanGeneration:
            return L10n.text("ai_settings.prefs.explain.medical_exam_plan_generation")
        }
    }
}
