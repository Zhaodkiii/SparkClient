import Foundation

/// 聊天图片附件在 `ChatAttachment.text` 中承载的 JSON 元数据（避免在 Core Data 存 base64 大图）。
struct ChatUploadedImageAttachmentMeta: Codable, Equatable, Sendable {
    let fileId: Int
    let fileUUID: String
    let originalName: String
    let fileMd5: String?
    let mimeType: String
    let filePath: String?
    let objectKey: String?
    let storageType: String?
    /// 若服务端 `file_path` 为可访问 HTTPS，则填入；否则为空，展示走本地缓存。
    let remoteURLString: String?
    let ocrText: String?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case fileUUID = "file_uuid"
        case originalName = "original_name"
        case fileMd5 = "file_md5"
        case mimeType = "mime_type"
        case filePath = "file_path"
        case objectKey = "object_key"
        case storageType = "storage_type"
        case remoteURLString = "remote_url"
        case ocrText = "ocr_text"
    }
}

enum ChatUploadedImageAttachmentCodec {
    static func encode(_ meta: ChatUploadedImageAttachmentMeta) -> String? {
        let data = try? JSONEncoder().encode(meta)
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decode(from text: String?) -> ChatUploadedImageAttachmentMeta? {
        let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard raw.isEmpty == false, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatUploadedImageAttachmentMeta.self, from: data)
    }
}
