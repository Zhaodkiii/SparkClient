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
    /// - Returns: 带远程文件记录的本地文件数组
    func execute(
        memberID: Int,
        files: [MedicalUploadLocalFile]
    ) async throws -> [MedicalUploadLocalFile] {
        var output: [MedicalUploadLocalFile] = []
        
        // 遍历所有待上传的本地文件
        for file in files {
            // 1. 从本地 URL 读取文件二进制数据
            let data = try Data(contentsOf: file.url)
            
            // 2. 调用文件传输服务进行上传
            // 这里指定了具体的业务类型 (businessType) 为 "medical_document_upload_source"
            // 并将 memberID 作为业务关联 ID (businessID)
            let record = try await fileTransferService.upload(
                ManagedFileUploadPayload(
                    data: data,
                    fileName: file.displayName,
                    businessType: "medical_document_upload_source",
                    businessID: "\(memberID)"
                )
            )
            
            // 3. 将服务器返回的远程记录 (record) 写回本地文件模型
            output.append(file.withRemoteFile(record))
        }
        
        // 4. 记录上传成功的统计日志
        logger.info("医疗文档源文件上传完成，count=\(output.count)", module: .medical)
        
        return output
    }
}
