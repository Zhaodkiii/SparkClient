import SwiftUI

/// 处方识别结果页（模块化：ResultPages/PrescriptionRecognitionResult）
struct PrescriptionRecognitionResultView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        PrescriptionRecognitionResultContentView(
            output: output,
            isSaving: isSaving,
            saveReceipt: saveReceipt,
            onBack: onBack,
            onSave: onSave
        )
        .navigationTitle(L10n.text("common.prescription"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Prescription result - Light") {
    CompatibleNavigationContainer {
        PrescriptionRecognitionResultView(
            output: .previewPrescriptionOutput,
            isSaving: false,
            saveReceipt: nil,
            onBack: {},
            onSave: {}
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Prescription result - Dark") {
    CompatibleNavigationContainer {
        PrescriptionRecognitionResultView(
            output: .previewPrescriptionOutput,
            isSaving: false,
            saveReceipt: nil,
            onBack: {},
            onSave: {}
        )
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
            typedResult: .prescription(
                PrescriptionRecognitionDraft(
                    medicalCase: 7,
                    prescriberName: "王医生",
                    institutionName: "仁和医院",
                    prescribedAt: "2026-04-12",
                    diagnosis: "上呼吸道感染",
                    batchNo: "RX-2201",
                    status: "active",
                    auditorName: nil,
                    auditedAt: nil,
                    extra: nil,
                    medications: [
                        MedicationRecognitionDraft(
                            genericName: "阿莫西林",
                            brandName: nil,
                            drugName: "阿莫西林胶囊",
                            dosageForm: "胶囊",
                            strength: "0.5g",
                            route: "口服",
                            dosePerTime: "1 粒",
                            doseValue: "1",
                            doseUnit: "粒",
                            frequencyCode: "TID",
                            period: "日",
                            timesPerPeriod: "3",
                            frequencyText: "每日 3 次",
                            durationDays: "5",
                            instructions: "饭后",
                            reminderEnabled: false,
                            reminderTimes: [],
                            sortOrder: "0",
                            extra: nil
                        )
                    ]
                )
            ),
            extractedJSON: "",
            payloadPreview: ""
        )
    }
}
