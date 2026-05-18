import Foundation

/// 聊天附件落盘下载：与 UI / ``ChatDetailViewModel`` 解耦，仅在 `FileTransferService` actor 上执行，避免
/// `ChatImageDownloadCoordinator` 在非 MainActor executor 上回调 `@MainActor` 对象导致的并发内存损坏（EXC_BAD_ACCESS）。
enum ChatAttachmentFileDownload {
    nonisolated static func downloadToLocalFile(
        attachment: ChatAttachment,
        fileTransferService: FileTransferService,
        logger: Logger
    ) async throws -> URL {
        let parsed = attachment.sparkClientOSSFileUUIDAndFileName()
        let fileUUID = parsed?.fileUUID ?? attachment.id.uuidString
        let remoteURL = attachment.url
        let originalName =
            parsed?.fileName
            ?? remoteURL?.lastPathComponent.removingPercentEncoding
            ?? "image.jpg"
        let mimeType = FileUtilities.mimeType(forName: originalName)

        // OSS objectKey 从 URL 路径反推（去掉首尾斜杠），供预签名 URL 生成与缓存命中判断。
        let objectKey: String? = remoteURL.map { url in
            url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        let managedFile = ManagedFileRecord(
            id: attachment.fileId ?? 0,
            fileUuid: fileUUID,
            filePath: remoteURL?.absoluteString ?? "",
            originalName: originalName,
            fileSize: 0,
            mimeType: mimeType,
            fileMd5: attachment.fileMd5,
            isPublic: false,
            businessType: ChatSendAttachmentAssembly.chatAttachmentBusinessType,
            businessId: "",
            createdAt: "",
            objectKey: objectKey,
            storageType: nil
        )

        // 优先命中本地缓存（上传时已落盘），避免不必要的网络请求。
        if let cached = await fileTransferService.cachedURL(file: managedFile) {
            return cached
        }

        guard remoteURL != nil else {
            throw SparkNetworkError.decoding(
                NSError(
                    domain: "ChatAttachmentDownload",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "附件缺少可下载地址且本地无缓存"]
                )
            )
        }

        logger.debug("聊天附件触发远端下载，fileID=\(managedFile.id)", module: .general)

        // 私有 OSS bucket 需用预签名 URL；获取失败则回退到直链（公开桶或调试场景）。
        if let key = objectKey, key.isEmpty == false {
            do {
                let presignedURL = try await fileTransferService.makePresignedDownloadURL(objectKey: key)
                let presignedRecord = ManagedFileRecord(
                    id: managedFile.id,
                    fileUuid: managedFile.fileUuid,
                    filePath: presignedURL.absoluteString,
                    originalName: managedFile.originalName,
                    fileSize: managedFile.fileSize,
                    mimeType: managedFile.mimeType,
                    fileMd5: managedFile.fileMd5,
                    isPublic: managedFile.isPublic,
                    businessType: managedFile.businessType,
                    businessId: managedFile.businessId,
                    createdAt: managedFile.createdAt,
                    objectKey: managedFile.objectKey,
                    storageType: managedFile.storageType
                )
                return try await fileTransferService.download(file: presignedRecord)
            } catch {
                logger.debug("预签名 URL 生成失败，回退直链下载: \(error.localizedDescription)", module: .general)
            }
        }

        return try await fileTransferService.download(file: managedFile)
    }
}
