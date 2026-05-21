import Foundation

/// 附件下载管线：从持久化任务表消费 pending 行，经 ``FileTransferService`` 落盘到文件缓存。
/// **不**把 `file://` 写回消息里的 `ChatAttachment.url`（该字段保留远端 https）。
actor ChatAttachmentPipeline {
    private let repository: any ChatRepository
    private let fileTransferService: FileTransferService
    private let logger: Logger

    init(
        repository: any ChatRepository,
        fileTransferService: FileTransferService,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.fileTransferService = fileTransferService
        self.logger = logger
    }

    func processPendingJobs(limit: Int = 8) async {
        let jobs = await repository.loadPendingAttachmentDownloadJobs(limit: limit)
        for job in jobs {
            await repository.updateAttachmentDownloadJob(id: job.id, state: .processing, localFileURLString: nil)
            do {
                let attachment = job.attachmentSnapshot
                guard let managedFile = attachment.managedFileRecordForDownload() else {
                    throw URLError(.unsupportedURL)
                }
                if let cached = await fileTransferService.cachedURL(file: managedFile) {
                    await repository.updateAttachmentDownloadJob(
                        id: job.id,
                        state: .completed,
                        localFileURLString: cached.absoluteString
                    )
                    continue
                }
                let localURL = try await fileTransferService.download(file: managedFile)
                await repository.updateAttachmentDownloadJob(
                    id: job.id,
                    state: .completed,
                    localFileURLString: localURL.absoluteString
                )
            } catch {
                logger.warning(
                    "聊天附件下载失败 job=\(String(job.id.uuidString.prefix(8))) error=\(error.localizedDescription)",
                    module: .general
                )
                await repository.updateAttachmentDownloadJob(id: job.id, state: .failed, localFileURLString: nil)
            }
        }
    }
}
