import Foundation

struct BindUploadedFilesToMedicalBusinessUseCase: Sendable {
    let binder: any MedicalDocumentAttachmentBinding

    func execute(
        uploadedFiles: [UploadedMedicalDocumentFile],
        kind: MedicalDocumentKind,
        receipt: MedicalDocumentSaveReceipt
    ) async {
        await binder.bind(uploadedFiles: uploadedFiles, kind: kind, receipt: receipt)
    }
}
