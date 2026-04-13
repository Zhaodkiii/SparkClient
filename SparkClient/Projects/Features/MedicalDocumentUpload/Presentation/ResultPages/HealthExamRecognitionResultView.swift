import SwiftUI

/// 体检报告识别结果页（模块化：ResultPages/HealthExamRecognitionResult）
struct HealthExamRecognitionResultView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        HealthExamRecognitionResultContentView(
            output: output,
            isSaving: isSaving,
            saveReceipt: saveReceipt,
            onBack: onBack,
            onSave: onSave
        )
        .navigationTitle(L10n.text("medical.upload.result.health_exam.nav_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Health exam result - Light") {
    NavigationView {
        HealthExamRecognitionResultView(
            output: .previewHealthExamOutput,
            isSaving: false,
            saveReceipt: nil,
            onBack: {},
            onSave: {}
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Health exam result - Dark") {
    NavigationView {
        HealthExamRecognitionResultView(
            output: .previewHealthExamOutput,
            isSaving: false,
            saveReceipt: nil,
            onBack: {},
            onSave: {}
        )
    }
    .preferredColorScheme(.dark)
}

private extension MedicalDocumentTypedExtractionOutput {
    static var previewHealthExamOutput: MedicalDocumentTypedExtractionOutput {
        MedicalDocumentTypedExtractionOutput(
            envelope: MedicalDocumentRecognitionEnvelope(
                memberID: 9,
                sourceFiles: [
                    MedicalUploadLocalFile(
                        url: URL(fileURLWithPath: "/tmp/health-exam.pdf"),
                        displayName: "年度体检报告.pdf",
                        mimeType: "application/pdf"
                    )
                ],
                rawOCRText: "",
                typeResolution: MedicalDocumentTypeResolution(
                    kind: .healthExamReport,
                    confidence: 0.95,
                    source: .ai,
                    reason: "命中体检报告字段"
                )
            ),
            typedResult: .healthExamReport(
                HealthExamRecognitionDraft(
                    institutionName: "仁和医院体检中心",
                    reportNo: "HE-2026-001",
                    examDate: "2026-04-12",
                    examType: "年度体检",
                    summary: "血脂略高，建议控制饮食并复查。",
                    items: [
                        MedicalReportItem(
                            category: "血常规",
                            subCategory: nil,
                            itemName: "白细胞计数",
                            itemCode: "WBC",
                            resultValue: "11.2",
                            unit: "10^9/L",
                            referenceRange: "3.5-9.5",
                            flag: "high",
                            resultAt: nil,
                            modality: nil,
                            bodyPart: nil,
                            diagnosis: nil,
                            extra: nil,
                            sortOrder: "1"
                        ),
                        MedicalReportItem(
                            category: "影像",
                            subCategory: "胸部CT",
                            itemName: "胸部CT平扫",
                            itemCode: "CT",
                            resultValue: "轻度纹理增多",
                            unit: nil,
                            referenceRange: nil,
                            flag: "abnormal",
                            resultAt: nil,
                            modality: nil,
                            bodyPart: "胸部",
                            diagnosis: "建议随访",
                            extra: nil,
                            sortOrder: "2"
                        ),
                        MedicalReportItem(
                            category: "尿常规",
                            subCategory: nil,
                            itemName: "尿蛋白",
                            itemCode: "PRO",
                            resultValue: "阴性",
                            unit: nil,
                            referenceRange: "阴性",
                            flag: "normal",
                            resultAt: nil,
                            modality: nil,
                            bodyPart: nil,
                            diagnosis: nil,
                            extra: nil,
                            sortOrder: "3"
                        )
                    ]
                )
            ),
            extractedJSON: "",
            payloadPreview: ""
        )
    }
}
