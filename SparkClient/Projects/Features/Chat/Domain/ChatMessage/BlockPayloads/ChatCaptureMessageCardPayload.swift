import Foundation

enum ChatCaptureCardType: String, Codable, CaseIterable, Sendable {
    case reportPhoto = "report_photo"
    case medicineBoxPhoto = "medicine_box_photo"
    case skinPhoto = "skin_photo"
}

nonisolated enum ChatCaptureCardStatus: String, Codable, Sendable {
    case pending
    case selected
    case uploading
    case uploaded
    case processing
    case completed
    case failed
    case cancelled
}

nonisolated enum ChatCaptureAttachmentSource: String, Codable, Sendable {
    case camera
    case photoLibrary
    case document
}

nonisolated struct ChatCaptureMessageCardPayload: Codable, Equatable, Sendable {
    let id: UUID
    let completionID: UUID?
    let cardType: ChatCaptureCardType
    let sourceToolCallID: String?
    var status: ChatCaptureCardStatus
    var selectedAttachments: [ChatInlineCapturedAttachment]
    var errorMessage: String?
    var resultSummary: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        completionID: UUID? = nil,
        cardType: ChatCaptureCardType,
        sourceToolCallID: String? = nil,
        status: ChatCaptureCardStatus = .pending,
        selectedAttachments: [ChatInlineCapturedAttachment] = [],
        errorMessage: String? = nil,
        resultSummary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.completionID = completionID
        self.cardType = cardType
        self.sourceToolCallID = sourceToolCallID
        self.status = status
        self.selectedAttachments = selectedAttachments
        self.errorMessage = errorMessage
        self.resultSummary = resultSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case completionID = "completionId"
        case cardType
        case sourceToolCallID = "sourceToolCallId"
        case status
        case selectedAttachments
        case errorMessage
        case resultSummary
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        completionID = try c.decodeIfPresent(UUID.self, forKey: .completionID)
        cardType = try c.decode(ChatCaptureCardType.self, forKey: .cardType)
        sourceToolCallID = try c.decodeIfPresent(String.self, forKey: .sourceToolCallID)
        status = try c.decodeIfPresent(ChatCaptureCardStatus.self, forKey: .status) ?? .pending
        selectedAttachments = try c.decodeIfPresent([ChatInlineCapturedAttachment].self, forKey: .selectedAttachments) ?? []
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        resultSummary = try c.decodeIfPresent(String.self, forKey: .resultSummary)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

nonisolated struct ChatInlineCapturedAttachment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let source: ChatCaptureAttachmentSource
    let kind: ChatComposerAttachmentKind
    let displayName: String
    let mimeType: String?
    let byteCount: Int
    var uploadProgress: Double
    var localPreviewURL: URL?
    var fileID: Int?
    var publicURL: URL?
    var fullCacheKey: String?
    var fileMd5: String?
    var ocrText: String?
    var compressedByteCount: Int?
    var errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case kind
        case displayName
        case mimeType
        case byteCount
        case uploadProgress
        case localPreviewURL = "localPreviewUrl"
        case fileID = "fileId"
        case publicURL = "publicUrl"
        case fullCacheKey
        case fileMd5
        case ocrText
        case compressedByteCount
        case errorMessage
    }

    init(
        id: UUID,
        source: ChatCaptureAttachmentSource,
        kind: ChatComposerAttachmentKind,
        displayName: String,
        mimeType: String?,
        byteCount: Int,
        uploadProgress: Double = 0,
        localPreviewURL: URL? = nil,
        fileID: Int? = nil,
        publicURL: URL? = nil,
        fullCacheKey: String? = nil,
        fileMd5: String? = nil,
        ocrText: String? = nil,
        compressedByteCount: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.displayName = displayName
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.uploadProgress = uploadProgress
        self.localPreviewURL = localPreviewURL
        self.fileID = fileID
        self.publicURL = publicURL
        self.fullCacheKey = fullCacheKey
        self.fileMd5 = fileMd5
        self.ocrText = ocrText
        self.compressedByteCount = compressedByteCount
        self.errorMessage = errorMessage
    }
}

nonisolated struct ToolAttachmentCapturePrompt: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let cardType: ChatCaptureCardType

    init(id: UUID = UUID(), cardType: ChatCaptureCardType) {
        self.id = id
        self.cardType = cardType
    }
}

nonisolated struct ToolAttachmentCaptureResult: Codable, Equatable, Sendable {
    let cardType: ChatCaptureCardType
    let attachments: [ChatInlineCapturedAttachment]
    let modelContextText: String
}
