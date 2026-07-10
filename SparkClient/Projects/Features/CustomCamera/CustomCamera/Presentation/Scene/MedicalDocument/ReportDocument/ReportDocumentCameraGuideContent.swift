import SwiftUI

/// 报告类引导页内容（插图 + tip 列表）。
struct ReportDocumentCameraGuideContent: View {
    let context: MedicalDocumentCameraContext
    let maxCaptureCount: Int
    let onDismiss: () -> Void

    private var tips: [String] {
        switch context {
        case .caseDocument:
            return [
                L10n.text(
                    "home.medical.case_document.camera.guide.tip.flat_surface",
                    fallback: "将病历放在平整桌面上"
                ),
                L10n.text(
                    "home.medical.case_document.camera.guide.tip.full_frame",
                    fallback: "保持纸张四边完整入框"
                ),
                L10n.text(
                    "home.medical.case_document.camera.guide.tip.no_glare",
                    fallback: "避免反光、阴影和手指遮挡"
                ),
                L10n.text(
                    "home.medical.case_document.camera.guide.tip.clear_text",
                    fallback: "拍清楚患者姓名、就诊日期、医院、科室、诊断与医嘱内容"
                ),
                String(
                    format: L10n.text(
                        "home.medical.case_document.camera.guide.tip.multi_page",
                        fallback: "多页病历可按顺序连续拍摄，本次最多 %d 张"
                    ),
                    locale: Locale.current,
                    maxCaptureCount
                )
            ]
        case .examinationReport, .healthExamReport:
            return [
                L10n.text(
                    "home.medical.examination_report.camera.guide.tip.flat_surface",
                    fallback: "将报告放在平整桌面上"
                ),
                L10n.text(
                    "home.medical.examination_report.camera.guide.tip.full_frame",
                    fallback: "保持纸张四边完整入框"
                ),
                L10n.text(
                    "home.medical.examination_report.camera.guide.tip.no_glare",
                    fallback: "避免反光、阴影和手指遮挡"
                ),
                L10n.text(
                    "home.medical.examination_report.camera.guide.tip.clear_text",
                    fallback: "拍清楚姓名、检查项目、时间、医院、所见和结论"
                ),
                String(
                    format: L10n.text(
                        "home.medical.examination_report.camera.guide.tip.multi_page",
                        fallback: "多页报告可按顺序连续拍摄，本次最多 %d 张"
                    ),
                    locale: Locale.current,
                    maxCaptureCount
                )
            ]
        case .prescription:
            return [
                L10n.text(
                    "home.medical.prescription.camera.guide.tip.flat_surface",
                    fallback: "将处方放在平整桌面上"
                ),
                L10n.text(
                    "home.medical.prescription.camera.guide.tip.full_frame",
                    fallback: "保持纸张四边完整入框"
                ),
                L10n.text(
                    "home.medical.prescription.camera.guide.tip.no_glare",
                    fallback: "避免反光、阴影和手指遮挡"
                ),
                L10n.text(
                    "home.medical.prescription.camera.guide.tip.clear_text",
                    fallback: "拍清楚患者姓名、开方医生、药品名称、规格、数量与用法用量"
                ),
                String(
                    format: L10n.text(
                        "home.medical.prescription.camera.guide.tip.multi_page",
                        fallback: "多页处方可按顺序连续拍摄，本次最多 %d 张"
                    ),
                    locale: Locale.current,
                    maxCaptureCount
                )
            ]
        case .medicationPlan:
            return [
                L10n.text(
                    "home.medical.medication_plan.camera.guide.tip.flat_surface",
                    fallback: "将用药说明放在平整桌面上"
                ),
                L10n.text(
                    "home.medical.medication_plan.camera.guide.tip.full_frame",
                    fallback: "保持纸张四边完整入框"
                ),
                L10n.text(
                    "home.medical.medication_plan.camera.guide.tip.no_glare",
                    fallback: "避免反光、阴影和手指遮挡"
                ),
                L10n.text(
                    "home.medical.medication_plan.camera.guide.tip.clear_text",
                    fallback: "拍清楚药品名称、规格、单次剂量、服用频次与起止时间"
                ),
                String(
                    format: L10n.text(
                        "home.medical.medication_plan.camera.guide.tip.multi_page",
                        fallback: "多页说明可按顺序连续拍摄，本次最多 %d 张"
                    ),
                    locale: Locale.current,
                    maxCaptureCount
                )
            ]
        case .medicineBox:
            return []
        }
    }

    var body: some View {
        MedicalDocumentCameraGuideHost(
            title: context.guideTitle,
            subtitle: context.guideSubtitle,
            disclaimer: context.guideDisclaimer,
            onDismiss: onDismiss
        ) {
            illustration
        } tips: {
            MedicalDocumentCameraGuideTipsCard(tips: tips, accentColor: context.accentColor)
        }
    }

    private var illustration: some View {
        ZStack {
            MedicalDocumentCameraViewfinderShape()
                .stroke(
                    context.accentColor,
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: 200, height: 282)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(context.accentColor.opacity(0.10))
                .frame(width: 150, height: 212)

            Image(systemName: context.bottomPanelIcon)
                .font(.system(size: 48, weight: .semibold))
                .foregroundColor(context.accentColor)
        }
        .frame(width: 220, height: 300)
    }
}
