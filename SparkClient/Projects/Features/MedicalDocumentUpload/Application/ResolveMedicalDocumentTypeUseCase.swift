import Foundation

struct ResolveMedicalDocumentTypeUseCase: Sendable {
    let resolver: any MedicalDocumentTypeResolving

    func execute(
        selectedKind: MedicalDocumentKind,
        mergedOCRText: String,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> MedicalDocumentTypeResolution {
        try cancellationToken?.checkCancellation()
        return try await resolver.resolve(
            selectedKind: selectedKind,
            mergedOCRText: mergedOCRText,
            cancellationToken: cancellationToken
        )
    }
}
