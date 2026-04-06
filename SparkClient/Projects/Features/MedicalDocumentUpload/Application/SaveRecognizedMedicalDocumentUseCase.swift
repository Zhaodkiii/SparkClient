import Foundation

struct SaveRecognizedMedicalDocumentUseCase: Sendable {
    let saver: any MedicalDocumentSaver

    func execute(
        memberID: Int,
        result: MedicalDocumentRecognitionResult,
        sourceFiles: [MedicalUploadLocalFile]
    ) async throws -> MedicalDocumentSaveReceipt {
        try await saver.save(memberID: memberID, result: result, sourceFiles: sourceFiles)
    }
}
