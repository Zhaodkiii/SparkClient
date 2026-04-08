import Foundation

protocol MedicalPromptBuilding: Sendable {
    func typeRecognitionPrompt(ocrText: String) -> String
    func extractionPrompt(for input: MedicalPromptInput) -> String
}

struct MedicalPromptInput: Sendable {
    let kind: MedicalDocumentKind
    let mergedOCRText: String
}

struct MedicalPromptFactory: MedicalPromptBuilding {
    private let localizer: PromptLocalizer

    init(localizer: PromptLocalizer = PromptLocalizer()) {
        self.localizer = localizer
    }

    func typeRecognitionPrompt(ocrText: String) -> String {
        localizer.medicalDocumentTypeRecognitionPrompt(ocrText: ocrText)
    }

    func extractionPrompt(for input: MedicalPromptInput) -> String {
        switch input.kind {
        case .auto:
            return localizer.medicalDocumentExtractionPrompt(ocrText: input.mergedOCRText)
        case .caseDocument:
            return localizer.medicalCaseExtractionPrompt(ocrText: input.mergedOCRText)
        case .healthExamReport:
            return localizer.healthExamExtractionPrompt(ocrText: input.mergedOCRText)
        case .medicalReport:
            return localizer.medicalReportExtractionPrompt(ocrText: input.mergedOCRText)
        case .prescription:
            return localizer.prescriptionExtractionPrompt(ocrText: input.mergedOCRText)
        case .medication:
            return localizer.medicationExtractionPrompt(ocrText: input.mergedOCRText)
        }
    }
}
