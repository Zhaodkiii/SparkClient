import Foundation

/// 聊天图片落盘下载：与 UI / ``ChatDetailViewModel`` 解耦，仅在 `FileTransferService` actor 上执行，避免
/// `ChatImageDownloadCoordinator` 在非 MainActor executor 上回调 `@MainActor` 对象导致的并发内存损坏（EXC_BAD_ACCESS）。
enum ChatAttachmentImageDownload {
    nonisolated static func downloadToLocalFile(
        attachment: ChatAttachment,
        fileTransferService: FileTransferService,
        logger: Logger
    ) async throws -> URL {
        guard let remoteURL = attachment.effectiveHTTPSImageDownloadURL else {
            // 常见根因：DB upsert 曾跳过写入导致内存/磁盘里仍是「空壳」image 附件；见 `ChatMessage.shouldPreferRemoteUserImageSyncData` 与 CoreData upsert。
//            let fid = attachment.fileId.map(String.init) ?? "-"
//            let hasURL = attachment.url != nil
//            let urlLen = attachment.url.map { $0.absoluteString.count } ?? 0
//            let textLen = attachment.text?.count ?? 0
//            let fk = attachment.fullCacheKey.map { "\($0.prefix(48))…" } ?? "nil"
//            let md5 = attachment.fileMd5.map { String($0.prefix(8)) } ?? "nil"
//            logger.warning(
//                "聊天图片下载缺少 https URL，id=\(String(attachment.id.uuidString.prefix(8))) type=\(attachment.type.rawValue) fileID=\(fid) hasRawURL=\(hasURL) rawURLLen=\(urlLen) textLen=\(textLen) fullCacheKey=\(fk) md5Prefix=\(md5)",
//                module: .general
//            )
            throw SparkNetworkError.decoding(
                NSError(
                    domain: "ChatImageDownload",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "图片缺少可下载地址"]
                )
            )
        }
        let resolvedPath = remoteURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = attachment.sparkClientOSSFileUUIDAndFileName()
        let fileUUID = parsed?.fileUUID ?? attachment.id.uuidString
        let originalName =
            parsed?.fileName
            ?? remoteURL.lastPathComponent.removingPercentEncoding
            ?? "image.jpg"
        let mimeType = FileUtilities.mimeType(forName: originalName)
        let managedFile = ManagedFileRecord(
            id: attachment.fileId ?? 0,
            fileUUID: fileUUID,
            filePath: resolvedPath,
            originalName: originalName,
            fileSize: 0,
            mimeType: mimeType,
            fileMd5: attachment.fileMd5,
            isPublic: false,
            businessType: ChatSendImageAssembly.chatAttachmentBusinessType,
            businessID: "",
            createdAt: "",
            objectKey: nil,
            storageType: nil
        )
        if let cached = await fileTransferService.cachedURL(file: managedFile) {
            return cached
        }
        logger.debug("聊天图片触发公共下载，fileID=\(managedFile.id)", module: .general)
        return try await fileTransferService.download(file: managedFile)
    }
}
