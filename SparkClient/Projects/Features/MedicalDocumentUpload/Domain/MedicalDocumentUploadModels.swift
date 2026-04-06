import Foundation

struct MedicalUploadLocalFile: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let displayName: String
    let mimeType: String?

    init(
        id: UUID = UUID(),
        url: URL,
        displayName: String,
        mimeType: String? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.mimeType = mimeType
    }
}

enum MedicalDocumentUploadMode: String, Codable, CaseIterable, Sendable {
    case general
    case medicalCase
    case healthExam
    case medicalExam
    case medication
}

struct MedicalDocumentRecognitionResult: Sendable, Equatable {
    let memberID: Int
    let requestedMode: MedicalDocumentUploadMode?
    let resolvedMode: MedicalDocumentUploadMode?
    let rawOCRText: String
    let extractedJSONString: String
    let extractedSummary: String?
    let serverPayloadPreview: String?
}

struct MedicalDocumentSaveReceipt: Sendable, Equatable {
    let recordID: Int
    let savedAt: Date
    let isSuccess: Bool
}
