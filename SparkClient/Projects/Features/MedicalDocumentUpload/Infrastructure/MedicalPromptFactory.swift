import Foundation

protocol MedicalPromptBuilding: Sendable {
    func extractionPrompt(for input: MedicalPromptInput) -> String
}

struct MedicalPromptInput: Sendable {
    let mode: MedicalDocumentUploadMode?
    let mergedOCRText: String
}

struct MedicalPromptFactory: MedicalPromptBuilding {
    private let localizer: PromptLocalizer

    init(localizer: PromptLocalizer = PromptLocalizer()) {
        self.localizer = localizer
    }

    func extractionPrompt(for input: MedicalPromptInput) -> String {
        localizer.medicalDocumentExtractionPrompt(ocrText: input.mergedOCRText)
    }
}
