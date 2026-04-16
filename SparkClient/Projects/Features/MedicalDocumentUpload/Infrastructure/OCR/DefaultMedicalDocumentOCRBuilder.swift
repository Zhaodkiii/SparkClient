import Foundation
import UniformTypeIdentifiers

struct DefaultMedicalDocumentOCRBuilder: MedicalDocumentOCRBuilding, Sendable {
    let ocrOrchestrator: OCROrchestrator

    func buildMergedOCRText(files: [MedicalUploadLocalFile]) async throws -> String {
        var chunks: [String] = []
        for (idx, file) in files.enumerated() {
            let ocr = try await recognize(file: file)
            chunks.append("=== File \(idx + 1): \(file.displayName) ===\n\(ocr.text)")
        }
        return chunks.joined(separator: "\n\n")
    }

    private func recognize(file: MedicalUploadLocalFile) async throws -> OCRRecognition {
        if isImage(url: file.url, mimeType: file.mimeType) {
            let data = try Data(contentsOf: file.url)
            return try await ocrOrchestrator.recognize(imageData: data, options: .medicalDefault)
        }
        return try await ocrOrchestrator.recognize(document: file.url, options: .medicalDefault)
    }

    private func isImage(url: URL, mimeType: String?) -> Bool {
        if let mimeType, let type = UTType(mimeType: mimeType), type.conforms(to: .image) {
            return true
        }
        if let extType = UTType(filenameExtension: url.pathExtension), extType.conforms(to: .image) {
            return true
        }
        return false
    }
}
