import Foundation

/// 网络模块的设备侧缓存中心。
/// 职责参考 purchases-ios 的 DeviceCache：
/// 1. 维护设备级缓存元数据
/// 2. 提供 UserDefaults + 文件系统双层存储
/// 3. 统一管理 ETag、本地响应体、用户/设备上下文、日志配置
final class DeviceCache: @unchecked Sendable {
    private enum Keys {
        static let currentUserID = "spark.device_cache.current_user_id"
        static let trustedDeviceID = "spark.device_cache.trusted_device_id"
        static let logLevel = "spark.device_cache.log_level"
    }

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let baseDirectory: URL
    private let logger: Logger

    private let cachedCurrentUserID: Atomic<String?>
    private let cachedTrustedDeviceID: Atomic<String?>
    private let cachedLogLevel: Atomic<LogLevel?>

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.logger = logger

        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.baseDirectory = caches.appendingPathComponent("SparkClient.DeviceCache", isDirectory: true)
        }

        self.cachedCurrentUserID = Atomic(userDefaults.string(forKey: Keys.currentUserID))
        self.cachedTrustedDeviceID = Atomic(userDefaults.string(forKey: Keys.trustedDeviceID))

        if let storedLevelRaw = userDefaults.object(forKey: Keys.logLevel) as? Int,
           let level = LogLevel(rawValue: storedLevelRaw) {
            self.cachedLogLevel = Atomic(level)
        } else {
            self.cachedLogLevel = Atomic(nil)
        }
    }

    var currentUserID: String? { cachedCurrentUserID.value }
    var currentUserIDInt: Int? { cachedCurrentUserID.value.flatMap(Int.init) }
    var trustedDeviceID: String? { cachedTrustedDeviceID.value }
    var persistedLogLevel: LogLevel? { cachedLogLevel.value }

    func cache(currentUserID: String) {
        userDefaults.set(currentUserID, forKey: Keys.currentUserID)
        cachedCurrentUserID.value = currentUserID
        logger.debug("已缓存当前用户 ID=\(currentUserID)", module: .cache)
    }

    func cache(currentUserID: Int64) {
        cache(currentUserID: String(currentUserID))
    }

    func cache(trustedDeviceID: String) {
        userDefaults.set(trustedDeviceID, forKey: Keys.trustedDeviceID)
        cachedTrustedDeviceID.value = trustedDeviceID
        logger.debug("已缓存可信设备 ID=\(trustedDeviceID)", module: .cache)
    }

    func cache(logLevel: LogLevel) {
        userDefaults.set(logLevel.rawValue, forKey: Keys.logLevel)
        cachedLogLevel.value = logLevel
        logger.info("已持久化日志级别=\(logLevel.symbol)", module: .cache)
    }

    func clearDeviceMetadata() {
        userDefaults.removeObject(forKey: Keys.currentUserID)
        userDefaults.removeObject(forKey: Keys.trustedDeviceID)
        cachedCurrentUserID.value = nil
        cachedTrustedDeviceID.value = nil
    }

    func clearAllCaches() {
        clearDeviceMetadata()
        userDefaults.removeObject(forKey: Keys.logLevel)
        cachedLogLevel.value = nil

        if fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.removeItem(at: baseDirectory)
        }
    }

    /// 删除磁盘上的 HTTP 条件请求（ETag / 304 合并用）缓存，不影响 UserDefaults 中的设备元数据或日志级别。
    /// 同时移除可能存在的旧版 `SparkClient.ETagCache` 目录。
    func clearETagResponseCache() {
        if fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.removeItem(at: baseDirectory)
        }
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let legacyETagDirectory = caches.appendingPathComponent("SparkClient.ETagCache", isDirectory: true)
        if fileManager.fileExists(atPath: legacyETagDirectory.path) {
            try? fileManager.removeItem(at: legacyETagDirectory)
        }
    }

    fileprivate func metadataURL(for key: String) -> URL {
        baseDirectory.appendingPathComponent("\(key).meta.json", isDirectory: false)
    }

    fileprivate func bodyURL(for key: String) -> URL {
        baseDirectory.appendingPathComponent("\(key).body", isDirectory: false)
    }
}

extension DeviceCache: ETagStore {
    func record(forKey key: String) -> ETagCacheRecord? {
        let url = metadataURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ETagCacheRecord.self, from: data)
    }

    func cachedBody(forKey key: String) -> Data? {
        try? Data(contentsOf: bodyURL(for: key))
    }

    func store(record: ETagCacheRecord, body: Data, forKey key: String) throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }

        try AtomicFileWriter.write(try JSONEncoder().encode(record), to: metadataURL(for: key))
        try AtomicFileWriter.write(body, to: bodyURL(for: key))
    }

    func removeCache(forKey key: String) {
        try? fileManager.removeItem(at: metadataURL(for: key))
        try? fileManager.removeItem(at: bodyURL(for: key))
    }
}
