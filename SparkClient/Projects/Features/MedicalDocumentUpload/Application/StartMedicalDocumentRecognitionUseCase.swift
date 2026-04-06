import Foundation

struct StartMedicalDocumentRecognitionUseCase: Sendable {
    let recognizer: any MedicalDocumentRecognizer

    func execute(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        mode: MedicalDocumentUploadMode? = nil
    ) async throws -> MedicalDocumentRecognitionResult {
        try await recognizer.recognize(memberID: memberID, files: files, mode: mode)
    }
}
