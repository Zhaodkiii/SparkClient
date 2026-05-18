import Foundation

/// 上传医疗文档文件的用例
/// 遵循 Sendable 协议以确保在 Swift 并发模型（Task/Actor）中安全传输
struct UploadMedicalDocumentFilesUseCase: Sendable {
    // 依赖注入：文件传输服务（负责底层的上传和缓存）
    let fileTransferService: FileTransferService
    // 依赖注入：日志记录器
    let logger: Logger

    init(
        fileTransferService: FileTransferService,
        logger: Logger = ConsoleLogger()
    ) {
        self.fileTransferService = fileTransferService
        self.logger = logger
    }

    /// 执行上传逻辑
    /// - Parameters:
    ///   - memberID: 成员 ID（用于业务关联）
    ///   - files: 需要上传的本地文件对象数组
    ///   - reuploadAll: 是否全部重新上传；为 `false` 时已有 `remoteFile` 的文件将跳过上传
    /// - Returns: 带远程文件记录的本地文件数组
    func execute(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        reuploadAll: Bool = true
    ) async throws -> [MedicalUploadLocalFile] {
        var output: [MedicalUploadLocalFile] = []
        var uploadedCount = 0
        var skippedCount = 0

        for file in files {
            if reuploadAll == false, let remoteFile = file.remoteFile {
                logger.info(
                    "已有远端文件记录，跳过上传 name=\(file.displayName) fileID=\(remoteFile.id)",
                    module: .medical
                )
                output.append(file)
                skippedCount += 1
                continue
            }

            let data = try Data(contentsOf: file.url)
            let record = try await fileTransferService.upload(
                ManagedFileUploadPayload(
                    data: data,
                    fileName: file.displayName,
                    businessType: "medical_document_upload_source",
                    businessId: "\(memberID)",
                    isPublic: false,
                    onUploadProgress: nil
                )
            )
            output.append(file.withRemoteFile(record))
            uploadedCount += 1
        }

        logger.info(
            "医疗文档源文件上传完成，total=\(output.count) 新上传=\(uploadedCount) 跳过=\(skippedCount)",
            module: .medical
        )

        return output
    }
}
