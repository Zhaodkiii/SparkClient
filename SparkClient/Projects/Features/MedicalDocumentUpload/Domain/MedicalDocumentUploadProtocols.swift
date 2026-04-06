import Foundation

protocol MedicalDocumentRecognizer: Sendable {
    func recognize(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        mode: MedicalDocumentUploadMode?
    ) async throws -> MedicalDocumentRecognitionResult
}

protocol MedicalDocumentSaver: Sendable {
    func save(
        memberID: Int,
        result: MedicalDocumentRecognitionResult,
        sourceFiles: [MedicalUploadLocalFile]
    ) async throws -> MedicalDocumentSaveReceipt
}
