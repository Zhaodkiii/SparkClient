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
    static var capabilityName: String { get }

    func resolve(
        selectedKind: MedicalDocumentKind,
        mergedOCRText: String,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> MedicalDocumentTypeResolution
}

extension MedicalDocumentTypeResolving {
    static var capabilityName: String { "medical_extraction" }
}

protocol TypedMedicalDocumentExtracting: Sendable {
    static var capabilityName: String { get }

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
        extractionInputSource: MedicalExtractionInputSource,
        resolution: MedicalDocumentTypeResolution,
        preferredModelName: String?,
        retryFeedback: MedicalExtractionRetryFeedback?,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> MedicalDocumentTypedExtractionOutput

    func extract(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        selectedKind: MedicalDocumentKind,
        cancellationToken: AIRuntimeCancellationToken?
    ) async throws -> MedicalDocumentTypedExtractionOutput
}

extension TypedMedicalDocumentExtracting {
    static var capabilityName: String { "medical_extraction" }
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
