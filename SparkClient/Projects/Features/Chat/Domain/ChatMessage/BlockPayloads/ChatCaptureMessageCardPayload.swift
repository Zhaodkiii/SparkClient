import Foundation

/// 服务端可独立发布新的材料采集卡类型，因此这里不能使用编译器合成的
/// `RawRepresentable + Codable` 解码。合成实现遇到未知字符串会抛错，进而让
/// 整个增量消息响应解码失败、游标无法推进。
nonisolated enum ChatCaptureCardType: RawRepresentable, Codable, CaseIterable, Sendable, Equatable {
    case reportPhoto
    case supplementaryReport
    case medicineBoxPhoto
    case skinPhoto
    /// 前向兼容：保留服务端原始值，但只读展示，不开放错误的上传入口。
    case unsupported(String)

    static let allCases: [ChatCaptureCardType] = [
        .reportPhoto,
        .supplementaryReport,
        .medicineBoxPhoto,
        .skinPhoto,
    ]

    init?(rawValue: String) {
        switch rawValue {
        case "report_photo": self = .reportPhoto
        case "supplementary_report": self = .supplementaryReport
        case "medicine_box_photo": self = .medicineBoxPhoto
        case "skin_photo": self = .skinPhoto
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .reportPhoto: return "report_photo"
        case .supplementaryReport: return "supplementary_report"
        case .medicineBoxPhoto: return "medicine_box_photo"
        case .skinPhoto: return "skin_photo"
        case .unsupported(let rawValue): return rawValue
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .unsupported(rawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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

/// 上传卡片材料的处理方式（由 `show_custom_message_card` 工具调用的 `upload_mode` 参数决定）。
/// - `inline`：消息内处理（默认）——卡片内上传 + OCR 后经工具 continuation 续跑对话。
/// - `composer`：插入输入框（与历史插入卡片版本一致）——材料进入输入框预览区，
///   自动上传 + OCR，随下一条消息发送，不在消息内处理。
nonisolated enum ChatCaptureUploadMode: String, Codable, Sendable {
    case inline
    case composer
}

nonisolated struct ChatCaptureMessageCardPayload: Codable, Equatable, Sendable {
    let id: UUID
    let completionID: UUID?
    let cardType: ChatCaptureCardType
    /// 材料处理方式（默认 `inline`；历史数据缺失该字段时按 `inline` 解码）。
    let uploadMode: ChatCaptureUploadMode
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
        uploadMode: ChatCaptureUploadMode = .inline,
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
        self.uploadMode = uploadMode
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
        case uploadMode
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
        uploadMode = try c.decodeIfPresent(ChatCaptureUploadMode.self, forKey: .uploadMode) ?? .inline
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
