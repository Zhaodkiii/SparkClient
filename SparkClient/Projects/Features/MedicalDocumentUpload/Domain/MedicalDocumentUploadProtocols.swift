import Foundation

protocol MedicalDocumentRecognizer: Sendable {
    func recognize(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        mode: MedicalDocumentUploadMode?,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> MedicalDocumentRecognitionResult
}

protocol MedicalDocumentTypeResolving: Sendable {
    func resolve(
        selectedKind: MedicalDocumentKind,
        mergedOCRText: String,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> MedicalDocumentTypeResolution
}

protocol TypedMedicalDocumentExtracting: Sendable {
    func recognizeOCRFiles(
        files: [MedicalUploadLocalFile],
        reRecognizeAll: Bool,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> [MedicalUploadLocalFile]

    func mergeOCRText(
        files: [MedicalUploadLocalFile],
        reRecognizeAll: Bool,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> String

    func resolveType(
        selectedKind: MedicalDocumentKind,
        mergedOCRText: String,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> MedicalDocumentTypeResolution

    func extractStructured(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        mergedOCRText: String,
        resolution: MedicalDocumentTypeResolution,
        preferredModelName: String?,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> MedicalDocumentTypedExtractionOutput

    func extract(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        selectedKind: MedicalDocumentKind,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> MedicalDocumentTypedExtractionOutput
}

protocol TypedMedicalDocumentSaving: Sendable {
    func save(
        output: MedicalDocumentTypedExtractionOutput
    ) async throws -> MedicalDocumentSaveReceipt
}

protocol MedicalDocumentAttachmentBinding: Sendable {
    func bind(
        uploadedFiles: [MedicalUploadLocalFile],
        kind: MedicalDocumentKind,
        receipt: MedicalDocumentSaveReceipt
    ) async
}
