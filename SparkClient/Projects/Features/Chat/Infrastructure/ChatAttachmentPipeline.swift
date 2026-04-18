import Foundation

/// 附件下载管线：从持久化任务表消费 pending 行，经 ``ChatAttachmentImageDownload`` 落盘到文件缓存。
/// **不**把 `file://` 写回消息里的 `ChatAttachment.url`（该字段保留远端 https），避免 UI 载荷构建与 SwiftUI `.task` 生命周期错乱导致 `EXC_BAD_ACCESS`。
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
                let dedupeKey = job.dedupeKey
                let fts = fileTransferService
                let log = logger
                let snapshot = job.attachmentSnapshot
                let localURL = try await ChatImageDownloadCoordinator.shared.cachedOrDownload(dedupeKey: dedupeKey) {
                    try await ChatAttachmentImageDownload.downloadToLocalFile(
                        attachment: snapshot,
                        fileTransferService: fts,
                        logger: log
                    )
                }
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
