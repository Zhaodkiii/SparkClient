import Foundation

protocol MedicalDocumentRecognizer: Sendable {
    func recognize(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        mode: MedicalDocumentUploadMode?
    ) async throws -> MedicalDocumentRecognitionResult
}

protocol MedicalDocumentTypeResolving: Sendable {
    func resolve(
        selectedKind: MedicalDocumentKind,
        mergedOCRText: String
    ) async throws -> MedicalDocumentTypeResolution
}

protocol MedicalDocumentOCRBuilding: Sendable {
    func buildMergedOCRText(files: [MedicalUploadLocalFile]) async throws -> String
}

protocol MedicalDocumentStructuredExtracting: Sendable {
    func extract(
        kind: MedicalDocumentKind,
        mergedOCRText: String
    ) async throws -> MedicalDocumentStructuredExtractionOutput
}

struct MedicalDocumentStructuredExtractionOutput: Sendable {
    let typedResult: MedicalDocumentTypedResult
    let extractedJSON: String
}

protocol TypedMedicalDocumentExtracting: Sendable {
    func extract(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        selectedKind: MedicalDocumentKind
    ) async throws -> MedicalDocumentTypedExtractionOutput
}

protocol TypedMedicalDocumentSaving: Sendable {
    func save(
        output: MedicalDocumentTypedExtractionOutput
    ) async throws -> MedicalDocumentSaveReceipt
}

protocol MedicalDocumentAttachmentBinding: Sendable {
    func bind(
        uploadedFiles: [UploadedMedicalDocumentFile],
        kind: MedicalDocumentKind,
        receipt: MedicalDocumentSaveReceipt
    ) async
}
