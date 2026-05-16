import Foundation

struct ExtractTypedMedicalDocumentUseCase: Sendable {
    let extractor: any TypedMedicalDocumentExtracting

    func mergeOCRText(
        files: [MedicalUploadLocalFile],
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> String {
        try cancellationToken?.checkCancellation()
        return try await extractor.mergeOCRText(files: files, cancellationToken: cancellationToken)
    }

    func resolveType(
        selectedKind: MedicalDocumentKind,
        mergedOCRText: String,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> MedicalDocumentTypeResolution {
        try cancellationToken?.checkCancellation()
        return try await extractor.resolveType(
            selectedKind: selectedKind,
            mergedOCRText: mergedOCRText,
            cancellationToken: cancellationToken
        )
    }

    func extractStructured(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        mergedOCRText: String,
        resolution: MedicalDocumentTypeResolution,
        preferredModelName: String? = nil,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> MedicalDocumentTypedExtractionOutput {
        try cancellationToken?.checkCancellation()
        return try await extractor.extractStructured(
            memberID: memberID,
            files: files,
            mergedOCRText: mergedOCRText,
            resolution: resolution,
            preferredModelName: preferredModelName,
            cancellationToken: cancellationToken
        )
    }

    func execute(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        selectedKind: MedicalDocumentKind,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> MedicalDocumentTypedExtractionOutput {
        try cancellationToken?.checkCancellation()
        return try await extractor.extract(
            memberID: memberID,
            files: files,
            selectedKind: selectedKind,
            cancellationToken: cancellationToken
        )
    }
}
