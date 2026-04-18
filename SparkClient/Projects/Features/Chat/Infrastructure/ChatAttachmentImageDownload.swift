import Foundation

/// 聊天附件落盘下载：与 UI / ``ChatDetailViewModel`` 解耦，仅在 `FileTransferService` actor 上执行，避免
/// `ChatImageDownloadCoordinator` 在非 MainActor executor 上回调 `@MainActor` 对象导致的并发内存损坏（EXC_BAD_ACCESS）。
enum ChatAttachmentFileDownload {
    nonisolated static func downloadToLocalFile(
        attachment: ChatAttachment,
        fileTransferService: FileTransferService,
        logger: Logger
    ) async throws -> URL {
        guard let remoteURL = attachment.url else {
            throw SparkNetworkError.decoding(
                NSError(
                    domain: "ChatAttachmentDownload",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "附件缺少可下载地址"]
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
            businessType: ChatSendAttachmentAssembly.chatAttachmentBusinessType,
            businessID: "",
            createdAt: "",
            objectKey: nil,
            storageType: nil
        )
        if let cached = await fileTransferService.cachedURL(file: managedFile) {
            return cached
        }
        logger.debug("聊天附件触发公共下载，fileID=\(managedFile.id)", module: .general)
        return try await fileTransferService.download(file: managedFile)
    }
}
