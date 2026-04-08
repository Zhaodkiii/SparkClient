import Foundation

struct UploadMedicalDocumentFilesUseCase: Sendable {
    let fileTransferService: FileTransferService
    let logger: Logger

    init(
        fileTransferService: FileTransferService,
        logger: Logger = ConsoleLogger()
    ) {
        self.fileTransferService = fileTransferService
        self.logger = logger
    }

    func execute(
        memberID: Int,
        files: [MedicalUploadLocalFile]
    ) async throws -> [UploadedMedicalDocumentFile] {
        var output: [UploadedMedicalDocumentFile] = []
        for file in files {
            let data = try Data(contentsOf: file.url)
            let record = try await fileTransferService.upload(
                ManagedFileUploadPayload(
                    data: data,
                    fileName: file.displayName,
                    businessType: "medical_document_upload_source",
                    businessID: "\(memberID)"
                )
            )
            output.append(UploadedMedicalDocumentFile(localFile: file, remoteFile: record))
        }
        logger.info("医疗文档源文件上传完成，count=\(output.count)", category: "medical_upload")
        return output
    }
}
