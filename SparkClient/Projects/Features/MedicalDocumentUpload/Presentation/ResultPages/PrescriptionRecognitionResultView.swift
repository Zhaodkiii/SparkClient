import SwiftUI

/// 处方识别结果页（模块化：ResultPages/PrescriptionRecognitionResult）
struct PrescriptionRecognitionResultView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel

    init(viewModel: MedicalDocumentUploadViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if viewModel.typedOutput != nil {
                PrescriptionRecognitionResultContentView(viewModel: viewModel)
            }
        }
        .navigationTitle(L10n.text("common.prescription"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Prescription result - Light") {
    CompatibleNavigationContainer {
        PrescriptionRecognitionResultView(viewModel: .preview(output: .previewPrescriptionOutput))
    }
    .preferredColorScheme(.light)
}

#Preview("Prescription result - Dark") {
    CompatibleNavigationContainer {
        PrescriptionRecognitionResultView(viewModel: .preview(output: .previewPrescriptionOutput))
    }
    .preferredColorScheme(.dark)
}

private extension MedicalDocumentTypedExtractionOutput {
    static var previewPrescriptionOutput: MedicalDocumentTypedExtractionOutput {
        MedicalDocumentTypedExtractionOutput(
            envelope: MedicalDocumentRecognitionEnvelope(
                memberID: 3,
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
            typedResult: .prescription([
                PrescriptionRecognitionDraft(
                    medicalCase: 7,
                    prescriberName: "王医生",
                    institutionName: "仁和医院",
                    prescribedAt: "2026-04-12",
                    diagnosis: "上呼吸道感染",
                    prescriptionNo: "RX-2201",
                    status: "active",
                    extra: nil,
                    medicationPlans: [
                        MedicationPlanRecognitionDraft(
                            medicineName: "阿莫西林胶囊",
                            medicineType: "抗感染用药",
                            brandName: nil,
                            dosageForm: "胶囊",
                            strength: "0.5g",
                            dosePerTime: "1 粒",
                            doseValue: "1",
                            doseUnit: "粒",
                            frequencyType: "daily",
                            frequencyText: "每日 3 次",
                            instructions: "饭后",
                            reminderEnabled: false,
                            reminderTimes: [],
                            sortOrder: "0",
                            extra: nil
                        )
                    ]
                )
            ]),
            extractedJSON: "",
            payloadPreview: ""
        )
    }
}
#endif
