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
        .navigationTitle(L10n.text("common.medicationPlan"))
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
                    kind: .medicationPlan,
                    confidence: 0.91,
                    source: .ai,
                    reason: "命中药品结构化字段"
                )
            ),
            typedResult: .medicationPlan([
                MedicationPlanRecognitionDraft(
                    medicineName: "氯雷他定片",
                    medicineType: "抗过敏用药",
                    brandName: nil,
                    dosageForm: "片剂",
                    strength: "10mg",
                    dosePerTime: "1 片",
                    doseValue: "1",
                    doseUnit: "片",
                    frequencyType: "daily",
                    frequencyText: "每日 1 次",
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
