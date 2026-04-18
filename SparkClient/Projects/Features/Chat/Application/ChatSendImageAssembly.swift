import Foundation

struct ChatPreparedAttachment: Equatable, Sendable {
    let previewID: UUID
    let kind: ChatComposerAttachmentKind
    let record: ManagedFileRecord
    let ocrText: String?
}

/// 组装聊天文件上传后的附件元数据与用户可见/模型可见正文（本地 OCR 路径）。
enum ChatSendAttachmentAssembly {
    nonisolated static let chatAttachmentBusinessType = "chat_attachment"

    nonisolated static func makeAttachment(
        kind: ChatComposerAttachmentKind,
        previewID: UUID,
        record: ManagedFileRecord,
        ocrText: String?,
        publicFullURL: URL?
    ) -> ChatAttachment {
        let trimmedOCR = ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = trimmedOCR.isEmpty ? nil : trimmedOCR
        let attachmentType: ChatAttachmentType = switch kind {
        case .image: .image
        case .pdf: .pdf
        case .file: .file
        }
        return ChatAttachment(
            id: previewID,
            type: attachmentType,
            url: publicFullURL,
            text: text,
            fileId: record.id,
            fullCacheKey: ChatAttachment.makeFullCacheKey(fileUUID: record.fileUUID, fileName: record.originalName),
            fileMd5: record.fileMd5
        )
    }
}
