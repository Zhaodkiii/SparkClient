import Foundation

protocol MedicalDocumentRecognizer: Sendable {
    func recognize(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        mode: MedicalDocumentUploadMode?
    ) async throws -> MedicalDocumentRecognitionResult
}

protocol MedicalDocumentSaver: Sendable {
    func save(
        memberID: Int,
        result: MedicalDocumentRecognitionResult,
        sourceFiles: [MedicalUploadLocalFile]
    ) async throws -> MedicalDocumentSaveReceipt
}

protocol MedicalDocumentTypeResolving: Sendable {
    func resolve(
        selectedKind: MedicalDocumentKind,
        mergedOCRText: String
    ) async throws -> MedicalDocumentTypeResolution
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
