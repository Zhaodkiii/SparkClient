import SwiftUI

/// 病例识别结果页（独立模块）
struct CaseRecognitionResultView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        MedicalDocumentTypedResultScaffoldView(
            pageTitle: pageTitle,
            output: output,
            isSaving: isSaving,
            saveReceipt: saveReceipt,
            onBack: onBack,
            onSave: onSave
        )
        .navigationTitle("病例")
    }

    private var pageTitle: String {
        if case .caseDocument(let draft) = output.typedResult {
            return "病例识别结果 - \(draft.title)"
        }
        return "病例识别结果"
    }
}
