import SwiftUI

/// 用药识别结果页（独立模块）
struct MedicationRecognitionResultView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        MedicalDocumentTypedResultScaffoldView(
            pageTitle: "用药识别结果",
            output: output,
            isSaving: isSaving,
            saveReceipt: saveReceipt,
            onBack: onBack,
            onSave: onSave
        )
        .navigationTitle("用药")
    }
}
