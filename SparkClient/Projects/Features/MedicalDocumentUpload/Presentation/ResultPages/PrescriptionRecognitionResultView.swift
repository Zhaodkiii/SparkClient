import SwiftUI

/// 处方识别结果页（模块化：ResultPages/PrescriptionRecognitionResult）
struct PrescriptionRecognitionResultView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel
    private let previewFamilyMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]?

    init(
        viewModel: MedicalDocumentUploadViewModel,
        previewFamilyMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]? = nil
    ) {
        self.viewModel = viewModel
        self.previewFamilyMedicineBoxes = previewFamilyMedicineBoxes
    }

    var body: some View {
        Group {
            if viewModel.typedOutput != nil {
                PrescriptionRecognitionResultContentView(
                    viewModel: viewModel,
                    previewFamilyMedicineBoxes: previewFamilyMedicineBoxes
                )
            }
        }
        .navigationTitle(L10n.text("common.prescription"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Prescription result - Light") {
    CompatibleNavigationContainer {
        PrescriptionRecognitionResultView(
            viewModel: .preview(output: .previewPrescriptionOutput),
            previewFamilyMedicineBoxes: PrescriptionRecognitionResultPreviewFixtures.familyMedicineBoxes
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Prescription result - Dark") {
    CompatibleNavigationContainer {
        PrescriptionRecognitionResultView(
            viewModel: .preview(output: .previewPrescriptionOutput),
            previewFamilyMedicineBoxes: PrescriptionRecognitionResultPreviewFixtures.familyMedicineBoxes
        )
    }
    .preferredColorScheme(.dark)
}

private extension MedicalDocumentTypedExtractionOutput {
    static var previewPrescriptionOutput: MedicalDocumentTypedExtractionOutput {
        MedicalDocumentTypedExtractionOutput(
            envelope: MedicalDocumentRecognitionEnvelope(
                memberID: 460,
                sourceFiles: [
                    MedicalUploadLocalFile(
                        url: URL(fileURLWithPath: "/tmp/rx-preview.pdf"),
                        displayName: "处方单.pdf",
                        mimeType: "application/pdf"
                    )
                ],
                rawOCRText: "",
                typeResolution: MedicalDocumentTypeResolution(
                    kind: .prescription,
                    confidence: 0.96,
                    source: .ai,
                    reason: "命中处方批次结构"
                )
            ),
            typedResult: .prescription(PrescriptionRecognitionResultPreviewFixtures.prescriptionDrafts),
            extractedJSON: "",
            payloadPreview: ""
        )
    }
}
#endif
