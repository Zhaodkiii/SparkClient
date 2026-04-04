import CryptoKit
import Foundation

actor FileTransferService {
    private let api: SparkFileAPI
    private let cacheManager: FileCacheManager
    private let logger: Logger

    init(
        api: SparkFileAPI,
        cacheManager: FileCacheManager,
        logger: Logger = ConsoleLogger()
    ) {
        self.api = api
        self.cacheManager = cacheManager
        self.logger = logger
    }

    @discardableResult
    func upload(_ payload: ManagedFileUploadPayload) async throws -> ManagedFileRecord {
        let provisionalUUID = UUID().uuidString

        _ = try await cacheManager.save(
            data: payload.data,
            fileUUID: provisionalUUID,
            fileName: payload.fileName
        )

        let mimeType = FileTransferService.mimeType(for: payload.fileName)
        let uploaded = try await api.upload(
            data: payload.data,
            fileName: payload.fileName,
            businessType: payload.businessType,
            businessID: payload.businessID,
            isPublic: payload.isPublic,
            mimeType: mimeType
        )

        _ = try await cacheManager.save(
            data: payload.data,
            fileUUID: uploaded.fileUUID,
            fileName: uploaded.originalName
        )

        logger.info("文件上传完成，file_id=\(uploaded.id)，uuid=\(uploaded.fileUUID)", category: "file_transfer")
        return uploaded
    }

    func download(file: ManagedFileRecord, forceRefresh: Bool = false) async throws -> URL {
        if !forceRefresh,
           let cachedURL = await cacheManager.cachedFileURL(fileUUID: file.fileUUID, fileName: file.originalName) {
            if let fileMd5 = file.fileMd5 {
                let valid = await cacheManager.validateMD5(fileUUID: file.fileUUID, fileName: file.originalName, expectedMD5: fileMd5)
                if valid {
                    logger.debug("命中本地缓存并通过 MD5 校验，file_id=\(file.id)", category: "file_transfer")
                    return cachedURL
                }
                try? await cacheManager.remove(fileUUID: file.fileUUID)
            } else {
                logger.debug("命中本地缓存，file_id=\(file.id)", category: "file_transfer")
                return cachedURL
            }
        }

        let data = try await api.downloadData(fileID: file.id)
        if let expectedMD5 = file.fileMd5 {
            let actualMD5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actualMD5.caseInsensitiveCompare(expectedMD5) == .orderedSame else {
                logger.error("下载文件 MD5 校验失败，file_id=\(file.id)，expected=\(expectedMD5)，actual=\(actualMD5)", category: "file_transfer")
                throw SparkNetworkError.decoding(NSError(domain: "SparkFileTransfer", code: -1, userInfo: [NSLocalizedDescriptionKey: "下载文件校验失败"]))
            }
        }

        let localURL = try await cacheManager.save(
            data: data,
            fileUUID: file.fileUUID,
            fileName: file.originalName
        )
        logger.info("文件下载并缓存完成，file_id=\(file.id)", category: "file_transfer")
        return localURL
    }

    func cachedURL(file: ManagedFileRecord) async -> URL? {
        await cacheManager.cachedFileURL(fileUUID: file.fileUUID, fileName: file.originalName)
    }

    func list(
        businessType: String? = nil,
        businessID: String? = nil,
        isPublic: Bool? = nil
    ) async throws -> [ManagedFileRecord] {
        try await api.list(businessType: businessType, businessID: businessID, isPublic: isPublic)
    }

    static func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "json": return "application/json"
        case "zip": return "application/zip"
        case "mp4": return "video/mp4"
        default: return "application/octet-stream"
        }
    }
}
