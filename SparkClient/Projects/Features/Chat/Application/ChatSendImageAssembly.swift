import Foundation

struct ChatPreparedImageAttachment: Equatable, Sendable {
    let previewID: UUID
    let record: ManagedFileRecord
    let ocrText: String?
}

/// 组装聊天图片上传后的附件元数据与用户可见/模型可见正文（本地 OCR 路径）。
enum ChatSendImageAssembly {
    /// 与 ZDK / OSSUploader 对齐的聊天附件业务类型。
    static let chatAttachmentBusinessType = "chat_attachment"

    static func remoteURLString(from record: ManagedFileRecord) -> String? {
        guard let path = record.filePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              path.isEmpty == false else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        return nil
    }

    static func makeAttachment(
        previewID: UUID,
        record: ManagedFileRecord,
        ocrText: String?,
        imageDeliveryModeRaw: String?
    ) -> ChatAttachment {
        let remote = remoteURLString(from: record)
        let meta = ChatUploadedImageAttachmentMeta(
            fileId: record.id,
            fileUUID: record.fileUUID,
            originalName: record.originalName,
            fileMd5: record.fileMd5,
            mimeType: record.mimeType,
            filePath: record.filePath,
            objectKey: record.objectKey,
            storageType: record.storageType,
            remoteURLString: remote,
            ocrText: ocrText
        )
        let text = ChatUploadedImageAttachmentCodec.encode(meta)
        let url = remote.flatMap { URL(string: $0) }
        return ChatAttachment(
            id: previewID,
            type: "image_url",
            url: url,
            text: text,
            imageDeliveryModeRaw: imageDeliveryModeRaw
        )
    }

    /// 本地 OCR + 文本送达：不向模型送像素，仅拼接可审计文本。
    static func buildLocalOCRUserContent(userText: String, attachmentsWithOCR: [(record: ManagedFileRecord, ocr: String)]) -> String {
        var blocks: [String] = []
        for item in attachmentsWithOCR {
            let urlLine = remoteURLString(from: item.record).map { "url: \($0)" } ?? "url: (pending)"
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
