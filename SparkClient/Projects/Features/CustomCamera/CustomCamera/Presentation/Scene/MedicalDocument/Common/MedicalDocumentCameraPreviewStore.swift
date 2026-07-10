import Combine
import Foundation
import UIKit

/// 医疗文档拍摄预览临时文件管理。
@MainActor
final class MedicalDocumentCameraPreviewStore: ObservableObject {
    @Published var previewInput: FilePreviewInput?

    private var previewTempFileURL: URL?
    private let logContext: String

    init(logContext: String) {
        self.logContext = logContext
    }

    func presentPreview(image: UIImage, displayName: String, fileTag: String) {
        cleanup()

        guard let data = image.jpegData(compressionQuality: 0.95) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("medical_document_preview_\(fileTag)_\(UUID().uuidString).jpg")

        do {
            try data.write(to: url, options: .atomic)
            previewTempFileURL = url
            previewInput = FilePreviewInput(fileURL: url, displayName: displayName)
        } catch {
            SparkLogger.log(
                level: .warning,
                module: .camera,
                message: "MedicalDocumentCameraSceneHost: context=\(logContext) preview temp file write failed tag=\(fileTag) error=\(error.localizedDescription)"
            )
        }
    }

    func cleanup() {
        if let previewTempFileURL {
            try? FileManager.default.removeItem(at: previewTempFileURL)
        }
        previewTempFileURL = nil
        previewInput = nil
    }
}
