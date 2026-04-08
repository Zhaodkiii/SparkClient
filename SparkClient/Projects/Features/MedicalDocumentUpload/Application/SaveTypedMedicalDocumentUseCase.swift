import Foundation

struct SaveTypedMedicalDocumentUseCase: Sendable {
    let saver: any TypedMedicalDocumentSaving

    func execute(output: MedicalDocumentTypedExtractionOutput) async throws -> MedicalDocumentSaveReceipt {
        try await saver.save(output: output)
    }
}
