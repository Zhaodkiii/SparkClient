import CryptoKit
import Foundation

/// 文件传输服务：负责文件的上传、下载、缓存管理及 MD5 校验
/// 使用 Actor 保证并发环境下状态访问的线程安全
actor FileTransferService {
    private let api: SparkFileAPI            // 远程 API 接口
    private let ossAPI: SparkOSSAPI
    private let ossClient: OSSClientWrapper
    private let ossConfigurationStore: SparkOSSConfigurationStore
    private let cacheManager: FileCacheManager // 本地缓存管理器
    private let logger: Logger               // 日志记录器

    init(
        api: SparkFileAPI,
        ossAPI: SparkOSSAPI,
        ossClient: OSSClientWrapper,
        ossConfigurationStore: SparkOSSConfigurationStore,
        cacheManager: FileCacheManager,
        logger: Logger = ConsoleLogger()
    ) {
        self.api = api
        self.ossAPI = ossAPI
        self.ossClient = ossClient
        self.ossConfigurationStore = ossConfigurationStore
        self.cacheManager = cacheManager
        self.logger = logger
    }

    /// 上传文件
    /// - Parameter payload: 包含文件数据和业务信息的负载
    /// - Returns: 服务器返回的文件记录
    @discardableResult
    func upload(_ payload: ManagedFileUploadPayload) async throws -> ManagedFileRecord {
        let fileUUID = UUID().uuidString
        let fileMD5 = FileUtilities.md5Hex(payload.data)
        let safeFileName = FileUtilities.sanitizeFileName(payload.fileName)

        // 上传前先缓存，失败可重试并保留本地副本
        _ = try await cacheManager.save(
            data: payload.data,
            fileUUID: fileUUID,
            fileName: safeFileName
        )

        let ymd = Self.dayFormatter.string(from: Date())
        let objectKey = FileUtilities.makeObjectKey(
            prefix: "SparkClient/\(ymd)",
            uuidString: fileUUID,
            filename: safeFileName
        )
        let mimeType = FileUtilities.mimeType(forName: safeFileName)

        let runtimeConfig = try await ossConfigurationStore.configurationForUpload(using: ossAPI)
        await MainActor.run {
            OSSManager.shared.updateConfiguration(
                endpoint: runtimeConfig.endpointURL,
                bucket: runtimeConfig.bucketName,
                region: runtimeConfig.region
            )
        }

        try await ossClient.putObject(
            data: payload.data,
            objectKey: objectKey,
            contentType: mimeType,
            progressCallback: payload.onUploadProgress.map { sendable in
                { progress in sendable(progress) }
            }
        )

        let uploaded = try await api.registerFile(.init(
            fileUUID: fileUUID,
            originalName: safeFileName,
            fileSize: payload.data.count,
            mimeType: mimeType,
            fileMd5: fileMD5,
            isPublic: payload.isPublic,
            businessType: payload.businessType,
            businessID: payload.businessID,
            filePath: objectKey,
            objectKey: objectKey,
            storageType: "oss"
        ))

        let cacheMatches = await cacheManager.validateMD5(
            fileUUID: fileUUID,
            fileName: safeFileName,
            expectedMD5: fileMD5
        )
        if !cacheMatches {
            logger.warning(
                "上传完成后本地缓存 MD5 与预期不一致，uuid=\(fileUUID)，name=\(safeFileName)",
                module: .cache
            )
        }

        logger.info("文件上传完成，file_id=\(uploaded.id)，uuid=\(uploaded.fileUUID)", module: .cache)
        return uploaded
    }

    /// 下载文件（带缓存检测机制）
    /// - Parameters:
    ///   - file: 要下载的文件记录
    ///   - forceRefresh: 是否强制跳过缓存重新下载
    /// - Returns: 文件在本地的存储路径 URL
    func download(file: ManagedFileRecord, forceRefresh: Bool = false) async throws -> URL {
        // 1. 检查本地缓存：如果不强制刷新，且本地存在该文件
        if !forceRefresh,
           let cachedURL = await cacheManager.cachedFileURL(fileUUID: file.fileUUID, fileName: file.originalName) {
            
            // 2. 如果记录中有 MD5，则进行完整性校验
            if let fileMd5 = file.fileMd5 {
                let valid = await cacheManager.validateMD5(fileUUID: file.fileUUID, fileName: file.originalName, expectedMD5: fileMd5)
                if valid {
                    logger.debug("命中本地缓存并通过 MD5 校验，file_id=\(file.id)", module: .cache)
                    return cachedURL
                }
                // 如果 MD5 校验失败，说明本地缓存损坏，移除它
                try? await cacheManager.remove(fileUUID: file.fileUUID)
            } else {
                // 如果没有 MD5 记录，则直接使用缓存
                logger.debug("命中本地缓存，file_id=\(file.id)", module: .cache)
                return cachedURL
            }
        }

        guard let rawPath = file.filePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawPath.isEmpty == false,
              let downloadURL = URL(string: rawPath) else {
            throw SparkNetworkError.decoding(
                NSError(domain: "SparkFileTransfer", code: -1, userInfo: [NSLocalizedDescriptionKey: "附件直链无效，无法下载"])
            )
        }
        logger.debug("使用附件直链下载，file_id=\(file.id)", module: .cache)
        let (data, _) = try await URLSession.shared.data(from: downloadURL)
        
        // 4. 下载后立即进行 MD5 校验，确保文件在传输过程中没有损坏
        if let expectedMD5 = file.fileMd5 {
            let actualMD5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actualMD5.caseInsensitiveCompare(expectedMD5) == .orderedSame else {
                logger.error("下载文件 MD5 校验失败，file_id=\(file.id)，expected=\(expectedMD5)，actual=\(actualMD5)", module: .cache)
                throw SparkNetworkError.decoding(NSError(domain: "SparkFileTransfer", code: -1, userInfo: [NSLocalizedDescriptionKey: "下载文件校验失败"]))
            }
        }

        // 5. 校验通过，存入本地缓存并返回路径
        let localURL = try await cacheManager.save(
            data: data,
            fileUUID: file.fileUUID,
            fileName: file.originalName
        )
        logger.info("文件下载并缓存完成，file_id=\(file.id)", module: .cache)
        return localURL
    }

    /// 获取文件的本地缓存路径（如果存在）
    func cachedURL(file: ManagedFileRecord) async -> URL? {
        await cacheManager.cachedFileURL(fileUUID: file.fileUUID, fileName: file.originalName)
    }

    /// 基于 OSS object key 生成客户端本地 presigned 下载 URL（不依赖 files/{id}/download-url）。
    func makePresignedDownloadURL(objectKey: String, expires: TimeInterval = 3600) async throws -> URL {
        let trimmed = objectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw SparkNetworkError.decoding(
                NSError(domain: "SparkFileTransfer", code: -1, userInfo: [NSLocalizedDescriptionKey: "objectKey 为空，无法生成下载链接"])
            )
        }
        let runtimeConfig = try await ossConfigurationStore.configurationForUpload(using: ossAPI)
        await MainActor.run {
            OSSManager.shared.updateConfiguration(
                endpoint: runtimeConfig.endpointURL,
                bucket: runtimeConfig.bucketName,
                region: runtimeConfig.region
            )
        }
        return try await ossClient.presignedURL(objectKey: trimmed, expires: expires)
    }

    /// 获取远程文件列表
    func list(
        businessType: String? = nil,
        businessID: String? = nil,
        isPublic: Bool? = nil
    ) async throws -> [ManagedFileRecord] {
        try await api.list(businessType: businessType, businessID: businessID, isPublic: isPublic)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

}
