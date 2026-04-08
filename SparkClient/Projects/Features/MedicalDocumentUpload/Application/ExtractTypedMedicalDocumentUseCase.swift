import Foundation

struct ExtractTypedMedicalDocumentUseCase: Sendable {
    let extractor: any TypedMedicalDocumentExtracting

    func execute(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        selectedKind: MedicalDocumentKind
    ) async throws -> MedicalDocumentTypedExtractionOutput {
        try await extractor.extract(memberID: memberID, files: files, selectedKind: selectedKind)
    }
}
