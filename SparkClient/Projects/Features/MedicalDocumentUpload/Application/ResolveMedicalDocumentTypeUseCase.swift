import Foundation

struct ResolveMedicalDocumentTypeUseCase: Sendable {
    let resolver: any MedicalDocumentTypeResolving

    func execute(
        selectedKind: MedicalDocumentKind,
        mergedOCRText: String
    ) async throws -> MedicalDocumentTypeResolution {
        try await resolver.resolve(selectedKind: selectedKind, mergedOCRText: mergedOCRText)
    }
}
