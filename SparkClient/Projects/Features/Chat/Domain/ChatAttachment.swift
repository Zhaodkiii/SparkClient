import Foundation

/// 聊天附件类型：对齐 Health `AttachmentType` 的文件类（`image` / `video` / `pdf` / `file`），
/// 并包含工具/流式 UI 所需的结构化键。
/// `RawValue` 即为 JSON / 服务端字段值，请勿随意改名。
/// 历史数据中的 `image_base64` / `image_url` 在解码时统一映射为 ``image``（见 ``ChatAttachmentType`` 的 `Codable` 实现）。
enum ChatAttachmentType: String, Equatable, Sendable, CaseIterable {
    // MARK: - File / media

    case image
    case video
    case pdf
    case file

    // MARK: - 工具 / 流式结构化附件

    case toolContent = "toolContent"
    case toolName = "toolName"
    case knowledgeCard = "knowledge_card"
    case locationsInfo = "locations_info"
    case routeInfo = "route_info"
    case healthInfo = "health_info"
    case healthSleepVisualization = "health_sleep_viz"
    case htmlContent = "htmlContent"
    case operationalState = "operationalState"
    case operationalDescription = "operationalDescription"
    case translatedText = "translatedText"
    case events = "events"
    case taskCards = "task_cards"
    case structuredHealthCards = "structured_health_cards"
    case captureMessageCard = "capture_message_card"
    case smallTaskCard = "small_task_card"
}

/// 单条聊天消息的结构化附件。
/// - 用户上传图片：`type == .image`，`url` 为可访问地址，`text` 存 OCR 纯文本（无 OCR 则为 `nil`）。
/// - 工具/知识卡等：`text` 存 JSON 或展示用字符串。
struct ChatAttachment: Equatable, Sendable {
    let id: UUID
    let type: ChatAttachmentType
    let url: URL?
    let text: String?
    /// 文件服务登记后的 `file_id`（可选）。
    let fileId: Int?
    /// 与 ``FileCacheManager`` 布局一致的缓存键：`{fileUUID小写}/{原始文件名}`。
    let fullCacheKey: String?
    /// 文件内容 MD5（小写十六进制），用于下载后与本地缓存校验。
    let fileMd5: String?

    nonisolated init(
        id: UUID = UUID(),
        type: ChatAttachmentType,
        url: URL? = nil,
        text: String? = nil,
        fileId: Int? = nil,
        fullCacheKey: String? = nil,
        fileMd5: String? = nil
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.text = text
        self.fileId = fileId
        self.fullCacheKey = fullCacheKey
        self.fileMd5 = fileMd5
    }

    nonisolated var isChatImageLike: Bool {
        switch type {
        case .image:
            return true
        default:
            return false
        }
    }

    nonisolated var isUserImageForMultimodal: Bool {
        switch type {
        case .image:
            return true
        default:
            return false
        }
    }

    nonisolated var isUserFileForLocalOCR: Bool {
        switch type {
        case .image, .pdf, .file:
            return true
        default:
            return false
        }
    }

    nonisolated var isGenericFileAttachment: Bool {
        switch type {
        case .pdf, .file:
            return true
        default:
            return false
        }
    }

    nonisolated func withText(_ newText: String?) -> ChatAttachment {
        ChatAttachment(
            id: id,
            type: type,
            url: url,
            text: newText,
            fileId: fileId,
            fullCacheKey: fullCacheKey,
            fileMd5: fileMd5
        )
    }

    nonisolated func replacing(
        type: ChatAttachmentType? = nil,
        url: URL? = nil,
        text: String? = nil,
        fullCacheKey: String? = nil,
        fileMd5: String? = nil
    ) -> ChatAttachment {
        ChatAttachment(
            id: id,
            type: type ?? self.type,
            url: url ?? self.url,
            text: text ?? self.text,
            fileId: fileId,
            fullCacheKey: fullCacheKey ?? self.fullCacheKey,
            fileMd5: fileMd5 ?? self.fileMd5
        )
    }
}

// MARK: - `ChatAttachmentType` Codable（兼容历史 `image_base64` / `image_url`，写入时仅使用 `image`）

extension ChatAttachmentType: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        switch raw {
        case "image_base64", "image_url":
            self = .image
        default:
            guard let value = ChatAttachmentType(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: c,
                    debugDescription: "Unknown ChatAttachmentType raw value: \(raw)"
                )
            }
            self = value
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Codable（解码兼容 `file_id` / `full_cache_key` / `file_md5` 与驼峰本地存储）

extension ChatAttachment: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case url
        case text
        case fileId
        case fullCacheKey
        case fileMd5
        case fileIdSnake = "file_id"
        case fullCacheKeySnake = "full_cache_key"
        case fileMd5Snake = "file_md5"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(ChatAttachmentType.self, forKey: .type)
        url = try c.decodeIfPresent(URL.self, forKey: .url)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        fileId = try c.decodeIfPresent(Int.self, forKey: .fileId)
            ?? c.decodeIfPresent(Int.self, forKey: .fileIdSnake)
        fullCacheKey = try c.decodeIfPresent(String.self, forKey: .fullCacheKey)
            ?? c.decodeIfPresent(String.self, forKey: .fullCacheKeySnake)
        fileMd5 = try c.decodeIfPresent(String.self, forKey: .fileMd5)
            ?? c.decodeIfPresent(String.self, forKey: .fileMd5Snake)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(fileId, forKey: .fileId)
        try c.encodeIfPresent(fullCacheKey, forKey: .fullCacheKey)
        try c.encodeIfPresent(fileMd5, forKey: .fileMd5)
    }
}

// MARK: - OSS URL（本客户端 `SparkClient/{ymd}/{uuid}/{filename}`）

extension ChatAttachment {
    /// 上传登记后写入附件的缓存键，与 ``FileCacheManager`` 使用的 `fileUUID` + `fileName` 一致。
    nonisolated static func makeFullCacheKey(fileUUID: String, fileName: String) -> String {
        "\(fileUUID.lowercased())/\(fileName)"
    }

    /// 从公开 OSS URL 路径解析上传时使用的 `fileUUID` 与对象内原始文件名（用于本地缓存命中）。
    nonisolated func sparkClientOSSFileUUIDAndFileName() -> (fileUUID: String, fileName: String)? {
        if let key = fullCacheKey?.trimmingCharacters(in: .whitespacesAndNewlines), key.isEmpty == false {
            let parts = key.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            if parts.count == 2, UUID(uuidString: parts[0]) != nil, parts[1].isEmpty == false {
                return (parts[0].lowercased(), parts[1])
            }
        }
        return Self.parseSparkClientOSSPath(url?.path ?? "")
    }

    /// `path` 为 URL.path，例如 `/SparkClient/20260418/{uuid}/photo.jpg`
    nonisolated static func parseSparkClientOSSPath(_ path: String) -> (fileUUID: String, fileName: String)? {
        let parts = path.split(separator: "/").map(String.init)
        guard let idx = parts.firstIndex(of: "SparkClient"), parts.count >= idx + 4 else { return nil }
        let datePart = parts[idx + 1]
        guard datePart.count == 8, datePart.allSatisfy({ $0.isNumber }) else { return nil }
        let uuidPart = parts[idx + 2]
        guard UUID(uuidString: uuidPart) != nil else { return nil }
        let nameSegments = Array(parts[(idx + 3)...])
        guard nameSegments.isEmpty == false else { return nil }
        let rawName = nameSegments.joined(separator: "/")
        let fileName = rawName.removingPercentEncoding ?? rawName
        guard fileName.isEmpty == false else { return nil }
        return (uuidPart, fileName)
    }
}

// MARK: - 图片下载 / 列表缩略图

extension ChatAttachment {
    /// 可用于 HTTPS 远程下载的图片地址（仅 `url`；内嵌 base64 / 文本里的链接由 UI 层 ``ChatImagePayloadBuilder`` 处理）。
    nonisolated var effectiveHTTPSImageDownloadURL: URL? {
        guard let u = url else { return nil }
        guard let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return u
    }

    /// 列表与详情、多次触发时去重用（优先 `fullCacheKey`，否则稳定 URL，再退 `id`）。
    nonisolated var imageDownloadDedupeKey: String {
        if let k = fullCacheKey?.trimmingCharacters(in: .whitespacesAndNewlines), k.isEmpty == false {
            return "full:\(k)"
        }
        if let u = effectiveHTTPSImageDownloadURL?.absoluteString {
            return "url:\(u)"
        }
        return "id:\(id.uuidString)"
    }
}
