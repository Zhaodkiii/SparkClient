import Foundation

struct StartMedicalDocumentRecognitionUseCase: Sendable {
    let recognizer: any MedicalDocumentRecognizer

    func execute(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        mode: MedicalDocumentUploadMode? = nil,
        cancellationToken: AIRuntimeCancellationToken? = nil
    ) async throws -> MedicalDocumentRecognitionResult {
        try cancellationToken?.checkCancellation()
        return try await recognizer.recognize(
            memberID: memberID,
            files: files,
            mode: mode,
            cancellationToken: cancellationToken
        )
    }
}
