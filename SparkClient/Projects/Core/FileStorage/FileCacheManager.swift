import CryptoKit
import Foundation

/// 文件缓存管理器：负责本地文件的持久化存储、读取、校验与清理
/// 使用 Actor 确保多线程环境下对文件系统操作的线程安全
actor FileCacheManager {
    private let fileManager: FileManager
    private let logger: Logger
    private let baseDirectory: URL
    private var accountNamespace: String = "guest"

    init(fileManager: FileManager = .default, logger: Logger = ConsoleLogger()) {
        self.fileManager = fileManager
        self.logger = logger

        // 1. 设置缓存根目录：优先使用沙盒的 Library/Caches 目录
        // 系统在磁盘空间极度不足时可能会清理此目录，但它比 Tmp 目录更持久
        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            self.baseDirectory = caches.appendingPathComponent("SparkClient.FileCache", isDirectory: true)
        } else {
            // 降级方案：使用临时目录
            self.baseDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SparkClient.FileCache", isDirectory: true)
        }
    }

    /// 获取缓存文件的本地 URL
    /// - Returns: 如果文件存在则返回 URL，否则返回 nil
    func cachedFileURL(fileUUID: String, fileName: String) -> URL? {
        let normalizedUUID = fileUUID.lowercased()
        let destination = fileURL(fileUUID: normalizedUUID, fileName: fileName)
        
        // 检查物理文件是否存在
        guard fileManager.fileExists(atPath: destination.path) else {
            return nil
        }
        return destination
    }

    /// 切换文件缓存账号命名空间。新项目不做旧缓存迁移，账号切换后自然读写新目录。
    func activateAccountContext(_ accountID: Int64) {
        accountNamespace = "account-\(accountID)"
        logger.info("文件缓存已切换到账号命名空间 accountID=\(accountID)", module: .cache)
    }

    /// 登出后回到访客命名空间，避免未登录态继续读写上一账号目录。
    func activateGuestContext() {
        accountNamespace = "guest"
        logger.info("文件缓存已切换到访客命名空间", module: .cache)
    }

    /// 将二进制数据保存到缓存
    /// - Returns: 最终保存的文件 URL
    @discardableResult
    func save(data: Data, fileUUID: String, fileName: String) throws -> URL {
        let normalizedUUID = fileUUID.lowercased()
        let directory = directoryURL(for: normalizedUUID)
        
        // 1. 确保该文件的专属目录（以 UUID 命名）已创建
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let destination = fileURL(fileUUID: normalizedUUID, fileName: fileName)
        
        // 2. 检查是否已存在同名且大小一致的文件，避免重复写入（秒传逻辑）
        if fileManager.fileExists(atPath: destination.path),
           let attrs = try? fileManager.attributesOfItem(atPath: destination.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue == data.count {
            return destination
        }

        // 3. 写入文件，使用 .atomic 选项确保写入的原子性（先写临时文件再重命名，防止崩溃导致数据损坏）
        try data.write(to: destination, options: [.atomic])
        logger.debug("文件缓存写入成功，uuid=\(normalizedUUID)，name=\(fileName)", module: .cache)
        return destination
    }

    /// 校验本地缓存文件的 MD5
    func validateMD5(fileUUID: String, fileName: String, expectedMD5: String) -> Bool {
        guard let url = cachedFileURL(fileUUID: fileUUID, fileName: fileName),
              let data = try? Data(contentsOf: url) else {
            return false
        }
        // 计算当前文件的 MD5 摘要并转为 16 进制字符串
        let digest = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        // 忽略大小写进行比对
        return digest.caseInsensitiveCompare(expectedMD5) == .orderedSame
    }

    /// 根据 UUID 移除特定文件的所有缓存记录
    func remove(fileUUID: String) throws {
        let directory = directoryURL(for: fileUUID.lowercased())
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
        logger.info("已移除文件缓存目录，uuid=\(fileUUID)", module: .cache)
    }

    /// 清空整个缓存根目录
    func clearAll() throws {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return }
        try fileManager.removeItem(at: baseDirectory)
        logger.info("已清理所有文件缓存", module: .cache)
    }

    /// 统计当前的缓存占用情况
    /// - Returns: (文件总数, 总字节大小)
    func cacheStatistics() -> (fileCount: Int, totalBytes: Int64) {
        guard fileManager.fileExists(atPath: baseDirectory.path),
              let enumerator = fileManager.enumerator(at: baseDirectory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return (0, 0)
        }

        var fileCount = 0
        var totalBytes: Int64 = 0
        // 递归遍历缓存目录下的所有文件
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            fileCount += 1
            totalBytes += Int64(values.fileSize ?? 0)
        }
        return (fileCount, totalBytes)
    }

    // MARK: - 私有辅助方法

    /// 每个文件根据 UUID 拥有独立的子目录，防止同名文件冲突
    private func directoryURL(for fileUUID: String) -> URL {
        baseDirectory
            .appendingPathComponent(accountNamespace, isDirectory: true)
            .appendingPathComponent(fileUUID, isDirectory: true)
    }

    /// 构建最终的文件保存路径
    private func fileURL(fileUUID: String, fileName: String) -> URL {
        directoryURL(for: fileUUID).appendingPathComponent(sanitizedFileName(fileName), isDirectory: false)
    }

    /// 清理文件名中的非法字符，防止跨平台存储或路径注入攻击
    private func sanitizedFileName(_ raw: String) -> String {
        // 定义路径分隔符等非法字符集
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let components = raw.components(separatedBy: invalid)
        // 将非法字符替换为下划线
        let collapsed = components.joined(separator: "_")
        return collapsed.isEmpty ? "unnamed_file" : collapsed
    }
}
