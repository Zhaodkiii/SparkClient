import Foundation

struct ExtractTypedMedicalDocumentUseCase: Sendable {
    let extractor: any TypedMedicalDocumentExtracting

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
