import SwiftUI

/// 检查报告识别结果页（模块化：ResultPages/MedicalReportRecognitionResult）
struct MedicalReportRecognitionResultView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel

    init(viewModel: MedicalDocumentUploadViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if viewModel.typedOutput != nil {
                MedicalReportRecognitionResultContentView(viewModel: viewModel)
            }
        }
        .navigationTitle(L10n.text("medical.upload.result.medical_report.nav_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Medical report result - Light") {
    CompatibleNavigationContainer {
        MedicalReportRecognitionResultView(viewModel: .preview(output: .previewMedicalReportOutput))
    }
    .preferredColorScheme(.light)
}

#Preview("Medical report result - Dark") {
    CompatibleNavigationContainer {
        MedicalReportRecognitionResultView(viewModel: .preview(output: .previewMedicalReportOutput))
    }
    .preferredColorScheme(.dark)
}

private extension MedicalDocumentTypedExtractionOutput {
    static var previewMedicalReportOutput: MedicalDocumentTypedExtractionOutput {
        MedicalDocumentTypedExtractionOutput(
            envelope: MedicalDocumentRecognitionEnvelope(
                memberID: 8,
                sourceFiles: [
                    MedicalUploadLocalFile(
                        url: URL(fileURLWithPath: "/tmp/exam-ct.pdf"),
                        displayName: "胸部CT报告.pdf",
                        mimeType: "application/pdf"
                    )
                ],
                rawOCRText: "",
                typeResolution: MedicalDocumentTypeResolution(
                    kind: .medicalReport,
                    confidence: 0.94,
                    source: .ai,
                    reason: "命中检查报告结构"
                )
            ),
            typedResult: .medicalReport([
                MedicalReportRecognitionDraft(
                    category: "laboratory",
                    title: "血常规",
                    hospital: "仁和医院",
                    doctor: "李医生",
                    content: "白细胞略高",
                    date: "2026-04-12",
                    details: []
                ),
                MedicalReportRecognitionDraft(
                    category: "imaging",
                    title: "胸部CT",
                    hospital: "仁和医院",
                    doctor: "王医生",
                    content: "双肺纹理增多，建议复查",
                    date: "2026-04-12",
                    details: []
                ),
                MedicalReportRecognitionDraft(
                    category: "pathology",
                    title: "病理活检",
                    hospital: "仁和医院",
                    doctor: "赵医生",
                    content: "慢性炎症改变",
                    date: "2026-04-11",
                    details: []
                )
            ]),
            extractedJSON: "",
            payloadPreview: ""
        )
    }
}
#endif
