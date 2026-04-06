import Foundation

struct BuildMedicalDocumentPreviewItemsUseCase: Sendable {
    func execute(files: [MedicalUploadLocalFile]) -> [FilePreviewInput] {
        files.map {
            FilePreviewInput(
                id: $0.id,
                fileURL: $0.url,
                displayName: $0.displayName,
                mimeType: $0.mimeType,
                utTypeIdentifier: nil
            )
        }
    }
}
