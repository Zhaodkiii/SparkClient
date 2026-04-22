import SwiftUI

/// 用药识别结果页（模块化：ResultPages/MedicationRecognitionResult）
struct MedicationRecognitionResultView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        MedicationRecognitionResultContentView(
            output: output,
            isSaving: isSaving,
            saveReceipt: saveReceipt,
            onBack: onBack,
            onSave: onSave
        )
        .navigationTitle(L10n.text("medical.upload.result.medication.nav_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Medication result - Light") {
    CompatibleNavigationContainer {
        MedicationRecognitionResultView(
            output: .previewMedicationOutput,
            isSaving: false,
            saveReceipt: nil,
            onBack: {},
            onSave: {}
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Medication result - Dark") {
    CompatibleNavigationContainer {
        MedicationRecognitionResultView(
            output: .previewMedicationOutput,
            isSaving: false,
            saveReceipt: nil,
            onBack: {},
            onSave: {}
        )
    }
    .preferredColorScheme(.dark)
}

private extension MedicalDocumentTypedExtractionOutput {
    static var previewMedicationOutput: MedicalDocumentTypedExtractionOutput {
        MedicalDocumentTypedExtractionOutput(
            envelope: MedicalDocumentRecognitionEnvelope(
                memberID: 5,
                sourceFiles: [
                    MedicalUploadLocalFile(
                        url: URL(fileURLWithPath: "/tmp/med-preview.jpg"),
                        displayName: "药盒照片.jpg",
                        mimeType: "image/jpeg"
                    )
                ],
                rawOCRText: "",
                typeResolution: MedicalDocumentTypeResolution(
                    kind: .medication,
                    confidence: 0.91,
                    source: .ai,
                    reason: "命中药品结构化字段"
                )
            ),
            typedResult: .medication([
                MedicationRecognitionDraft(
                    genericName: "氯雷他定",
                    brandName: nil,
                    drugName: "氯雷他定片",
                    dosageForm: "片剂",
                    strength: "10mg",
                    route: "口服",
                    dosePerTime: "1 片",
                    doseValue: "1",
                    doseUnit: "片",
                    frequencyCode: "QD",
                    period: "日",
                    timesPerPeriod: "1",
                    frequencyText: "每日 1 次",
                    durationDays: "7",
                    instructions: "睡前服",
                    reminderEnabled: false,
                    reminderTimes: [],
                    sortOrder: "0",
                    extra: nil
                )
            ]),
            extractedJSON: "",
            payloadPreview: ""
        )
    }
}
