import SwiftUI

/// 医疗文档相机业务上下文。只表达相机场景语义，不依赖 Home 的 `MedicalDocumentKind`。
enum MedicalDocumentCameraContext: Hashable {
    case caseDocument
    case examinationReport
    case healthExamReport
    case medicationPlan
    case prescription
    case medicineBox

    var isReportDocument: Bool {
        self != .medicineBox
    }

    var layoutProfile: MedicalDocumentCameraLayoutProfile {
        switch self {
        case .medicineBox:
            return .medicineBox
        case .caseDocument, .examinationReport, .healthExamReport, .medicationPlan, .prescription:
            return .reportDocument
        }
    }

    var accentColor: Color {
        switch self {
        case .medicineBox:
            return Color(uiColor: .systemPurple)
        case .caseDocument, .examinationReport, .healthExamReport, .medicationPlan, .prescription:
            return Color(uiColor: .systemBlue)
        }
    }

    var logContext: String {
        switch self {
        case .caseDocument: return "caseDocument"
        case .examinationReport: return "examinationReport"
        case .healthExamReport: return "healthExamReport"
        case .medicationPlan: return "medicationPlan"
        case .prescription: return "prescription"
        case .medicineBox: return "medicineBox"
        }
    }

    var guideStorageKey: String {
        switch self {
        case .caseDocument:
            return "spark.case_document.camera.guide.has_seen"
        case .examinationReport, .healthExamReport:
            return "spark.examination_report.camera.guide.has_seen"
        case .prescription:
            return "spark.prescription.camera.guide.has_seen"
        case .medicationPlan:
            return "spark.medication_plan.camera.guide.has_seen"
        case .medicineBox:
            return "spark.medicine_box.camera.guide.has_seen"
        }
    }

    var navigationTitle: String {
        switch self {
        case .caseDocument:
            return L10n.text("home.medical.case_document.camera.title", fallback: "病历")
        case .examinationReport:
            return L10n.text("home.medical.examination_report.camera.title", fallback: "检查报告")
        case .healthExamReport:
            return L10n.text("home.medical.health_exam_report.camera.title", fallback: "体检报告")
        case .medicationPlan:
            return L10n.text("home.medical.medication_plan.camera.title", fallback: "服药计划")
        case .prescription:
            return L10n.text("home.medical.prescription.camera.title", fallback: "处方单")
        case .medicineBox:
            return L10n.text("home.medical.medicine_box.camera.title", fallback: "药盒")
        }
    }

    var guideTitle: String {
        switch self {
        case .caseDocument:
            return L10n.text("home.medical.case_document.camera.guide.title", fallback: "病历拍摄")
        case .examinationReport:
            return L10n.text("home.medical.examination_report.camera.guide.title", fallback: "检查报告拍摄")
        case .healthExamReport:
            return L10n.text("home.medical.health_exam_report.camera.guide.title", fallback: "体检报告拍摄")
        case .medicationPlan:
            return L10n.text("home.medical.medication_plan.camera.guide.title", fallback: "服药计划拍摄")
        case .prescription:
            return L10n.text("home.medical.prescription.camera.guide.title", fallback: "处方单拍摄")
        case .medicineBox:
            return L10n.text("home.medical.medicine_box.camera.guide.title", fallback: "用药 AI 拍照识别")
        }
    }

    var guideSubtitle: String {
        switch self {
        case .caseDocument:
            return L10n.text(
                "home.medical.case_document.camera.guide.subtitle",
                fallback: "拍摄门诊病历、出院小结或相关附件，保持文字清晰完整。"
            )
        case .examinationReport:
            return L10n.text(
                "home.medical.examination_report.camera.guide.subtitle",
                fallback: "将报告平放，保持四边完整入框，文字清晰无遮挡。"
            )
        case .healthExamReport:
            return L10n.text(
                "home.medical.health_exam_report.camera.guide.subtitle",
                fallback: "体检报告页数较多，可按顺序连续拍摄，保持每页清晰完整。"
            )
        case .medicationPlan:
            return L10n.text(
                "home.medical.medication_plan.camera.guide.subtitle",
                fallback: "拍摄处方、用药说明或服药计划表，保持药品名称与服用频次清晰可见。"
            )
        case .prescription:
            return L10n.text(
                "home.medical.prescription.camera.guide.subtitle",
                fallback: "将处方平放，保持四边完整入框，药名、剂量与用法清晰可见。"
            )
        case .medicineBox:
            return L10n.text(
                "home.medical.medicine_box.camera.guide.subtitle",
                fallback: "拍摄前请准备好：\n1. 药盒正面图\n2. 保质期或生产日期图\n3. 药品说明书"
            )
        }
    }

    var defaultPrompt: String {
        switch self {
        case .caseDocument:
            return L10n.text(
                "home.medical.case_document.camera.prompt.default",
                fallback: "保持病历四边完整入框，文字清晰无遮挡"
            )
        case .examinationReport, .healthExamReport:
            return L10n.text(
                "home.medical.examination_report.camera.prompt.default",
                fallback: "保持报告四边完整入框，文字清晰无遮挡"
            )
        case .medicationPlan:
            return L10n.text(
                "home.medical.medication_plan.camera.prompt.default",
                fallback: "保持用药说明四边完整入框，药品与频次清晰可见"
            )
        case .prescription:
            return L10n.text(
                "home.medical.prescription.camera.prompt.default",
                fallback: "保持处方四边完整入框，文字清晰无遮挡"
            )
        case .medicineBox:
            return L10n.text(
                "home.medical.medicine_box.camera.prompt.front",
                fallback: "保证药品名称、品牌、规格完整，拍摄清晰"
            )
        }
    }

    var pagePromptFormat: String {
        switch self {
        case .caseDocument:
            return L10n.text(
                "home.medical.case_document.camera.prompt.page",
                fallback: "第 %d 张 · 保持病历四边完整入框"
            )
        case .examinationReport, .healthExamReport:
            return L10n.text(
                "home.medical.examination_report.camera.prompt.page",
                fallback: "第 %d 张 · 保持报告四边完整入框"
            )
        case .medicationPlan:
            return L10n.text(
                "home.medical.medication_plan.camera.prompt.page",
                fallback: "第 %d 张 · 保持用药说明四边完整入框"
            )
        case .prescription:
            return L10n.text(
                "home.medical.prescription.camera.prompt.page",
                fallback: "第 %d 张 · 保持处方四边完整入框"
            )
        case .medicineBox:
            return defaultPrompt
        }
    }

    var emptyValidationMessage: String {
        switch self {
        case .caseDocument:
            return L10n.text(
                "home.medical.case_document.camera.validation.empty",
                fallback: "请先拍摄病历图片"
            )
        case .examinationReport, .healthExamReport:
            return L10n.text(
                "home.medical.examination_report.camera.validation.empty",
                fallback: "请先拍摄报告图片"
            )
        case .medicationPlan:
            return L10n.text(
                "home.medical.medication_plan.camera.validation.empty",
                fallback: "请先拍摄服药计划图片"
            )
        case .prescription:
            return L10n.text(
                "home.medical.prescription.camera.validation.empty",
                fallback: "请先拍摄处方图片"
            )
        case .medicineBox:
            return L10n.text(
                "home.medical.medicine_box.camera.validation.missing_both",
                fallback: "请先拍摄药盒正面和保质期"
            )
        }
    }

    var captureLimitMessage: String {
        switch self {
        case .caseDocument:
            return L10n.text(
                "home.medical.case_document.camera.validation.limit",
                fallback: "已达到本次拍摄上限"
            )
        case .examinationReport, .healthExamReport:
            return L10n.text(
                "home.medical.examination_report.camera.validation.limit",
                fallback: "已达到本次拍摄上限"
            )
        case .medicationPlan:
            return L10n.text(
                "home.medical.medication_plan.camera.validation.limit",
                fallback: "已达到本次拍摄上限"
            )
        case .prescription:
            return L10n.text(
                "home.medical.prescription.camera.validation.limit",
                fallback: "已达到本次拍摄上限"
            )
        case .medicineBox:
            return L10n.text(
                "home.medical.examination_report.camera.validation.limit",
                fallback: "已达到本次拍摄上限"
            )
        }
    }

    var previewPageFormat: String {
        switch self {
        case .caseDocument:
            return L10n.text("home.medical.case_document.camera.preview.page", fallback: "第 %d 张")
        case .examinationReport, .healthExamReport:
            return L10n.text("home.medical.examination_report.camera.preview.page", fallback: "第 %d 张")
        case .medicationPlan:
            return L10n.text("home.medical.medication_plan.camera.preview.page", fallback: "第 %d 张")
        case .prescription:
            return L10n.text("home.medical.prescription.camera.preview.page", fallback: "第 %d 张")
        case .medicineBox:
            return L10n.text("home.medical.examination_report.camera.preview.page", fallback: "第 %d 张")
        }
    }

    var bottomPanelIcon: String {
        switch self {
        case .caseDocument:
            return "doc.text.fill"
        case .examinationReport, .healthExamReport:
            return "doc.text.fill"
        case .medicationPlan:
            return "capsule.fill"
        case .prescription:
            return "pills.fill"
        case .medicineBox:
            return "cross.case.fill"
        }
    }

    var guideDisclaimer: String {
        switch self {
        case .caseDocument:
            return L10n.text(
                "home.medical.case_document.camera.guide.disclaimer",
                fallback: "识别结果请以病历原件为准"
            )
        case .examinationReport, .healthExamReport:
            return L10n.text(
                "home.medical.examination_report.camera.guide.disclaimer",
                fallback: "识别结果请以报告原件为准"
            )
        case .medicationPlan:
            return L10n.text(
                "home.medical.medication_plan.camera.guide.disclaimer",
                fallback: "识别结果请以用药说明原件为准"
            )
        case .prescription:
            return L10n.text(
                "home.medical.prescription.camera.guide.disclaimer",
                fallback: "识别结果请以处方原件为准"
            )
        case .medicineBox:
            return L10n.text(
                "home.medical.medicine_box.camera.guide.disclaimer",
                fallback: "识别结果请以药品包装和说明书为准"
            )
        }
    }

    var emptyThumbnailIcon: String {
        switch self {
        case .caseDocument, .examinationReport, .healthExamReport:
            return "doc.text"
        case .medicationPlan:
            return "capsule"
        case .prescription:
            return "pills"
        case .medicineBox:
            return "cross.case"
        }
    }
}
