import Foundation

struct ChatPreparedImageAttachment: Equatable, Sendable {
    let previewID: UUID
    let record: ManagedFileRecord
    let ocrText: String?
}

/// 组装聊天图片上传后的附件元数据与用户可见/模型可见正文（本地 OCR 路径）。
enum ChatSendImageAssembly {
    nonisolated static let chatAttachmentBusinessType = "chat_attachment"

    nonisolated static func makeAttachment(
        previewID: UUID,
        record: ManagedFileRecord,
        ocrText: String?,
        publicFullURL: URL?
    ) -> ChatAttachment {
        let trimmedOCR = ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = trimmedOCR.isEmpty ? nil : trimmedOCR
        return ChatAttachment(
            id: previewID,
            type: .image,
            url: publicFullURL,
            text: text,
            fileId: record.id,
            fullCacheKey: ChatAttachment.makeFullCacheKey(fileUUID: record.fileUUID, fileName: record.originalName),
            fileMd5: record.fileMd5
        )
    }

    nonisolated static func buildLocalOCRUserContent(userText: String, attachmentsWithOCR: [(record: ManagedFileRecord, ocr: String)]) -> String {
        var blocks: [String] = []
        for item in attachmentsWithOCR {
            let urlLine: String = {
                if let path = item.record.filePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                   path.hasPrefix("http://") || path.hasPrefix("https://") {
                    return "url: \(path)"
                }
                return "url: (pending)"
            }()
            let ocr = item.ocr.trimmingCharacters(in: .whitespacesAndNewlines)
            blocks.append(
                """
                【图片附件】file_id=\(item.record.id) file_uuid=\(item.record.fileUUID)
                \(urlLine)
                【图片识别】
                \(ocr.isEmpty ? "(无文字)" : ocr)
                """
            )
        }
        let trimmedUser = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUser.isEmpty == false {
            blocks.append("【用户输入】\n\(trimmedUser)")
        }
        return blocks.joined(separator: "\n\n")
    }
}
