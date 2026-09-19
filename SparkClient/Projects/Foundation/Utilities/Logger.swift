import Foundation
import os

enum LogLevel: Int, CaseIterable, Codable, Sendable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4

    nonisolated var symbol: String {
        switch self {
        case .verbose: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

typealias InternalLogHandler = @Sendable (
    _ level: LogLevel,
    _ module: LogModule,
    _ message: String
) -> Void

nonisolated(unsafe) private let sparkLogLevelStorage = Atomic<LogLevel>(.info)
nonisolated(unsafe) private let sparkLogHandlerStorage = Atomic<InternalLogHandler>(SparkLogger.defaultHandler)
nonisolated(unsafe) private let sparkLogSubsystemStorage = Atomic<String>("SparkClient")

/// 网络与基础设施统一日志中心。
enum SparkLogger {
    nonisolated static var logLevel: LogLevel {
        get { sparkLogLevelStorage.value }
        set { sparkLogLevelStorage.value = newValue }
    }

    /// 保留字段（兼容旧配置）；默认输出格式不再包含 subsystem。
    nonisolated static var subsystem: String {
        get { sparkLogSubsystemStorage.value }
        set { sparkLogSubsystemStorage.value = newValue }
    }

    nonisolated static func configure(
        level: LogLevel,
        subsystem: String? = nil,
        handler: InternalLogHandler? = nil
    ) {
        sparkLogLevelStorage.value = level
        if let subsystem {
            sparkLogSubsystemStorage.value = subsystem
        }
        if let handler {
            sparkLogHandlerStorage.value = handler
        }
    }

    nonisolated static func reset() {
        sparkLogLevelStorage.value = .info
        sparkLogSubsystemStorage.value = "SparkClient"
        sparkLogHandlerStorage.value = defaultHandler
    }

    nonisolated static func isEnabled(_ level: LogLevel) -> Bool {
        level.rawValue >= sparkLogLevelStorage.value.rawValue
    }

    nonisolated static func log(
        level: LogLevel,
        module: LogModule,
        message: String
    ) {
        guard isEnabled(level) else { return }
        sparkLogHandlerStorage.value(level, module, message)
    }

    /// Unified Logging / Xcode 控制台会把超长单条日志截成 `<…>`（约 32KB）。
    /// 调试完整转储时按 UTF-8 分片走 `print`，避免 JSON 中途被截断。
    nonisolated static func debugUntruncated(_ message: String, module: LogModule) {
        guard isEnabled(.debug) else { return }
        let chunks = utf8Chunks(message, maxBytes: untruncatedChunkUTF8Bytes)
        sparkLogHandlerStorage.value(
            .debug,
            module,
            "完整调试输出 chars=\(message.count) parts=\(chunks.count)"
        )
        if chunks.count <= 1 {
            print(message)
            return
        }
        let total = chunks.count
        for (index, chunk) in chunks.enumerated() {
            print("[\(index + 1)/\(total)]\n\(chunk)")
        }
    }

    /// 单片低于 os.Logger 动态字符串约 1024 字符的截断阈值，并给日志前缀留余量。
    nonisolated fileprivate static let untruncatedChunkUTF8Bytes = 900

    nonisolated private static func utf8Chunks(_ text: String, maxBytes: Int) -> [String] {
        precondition(maxBytes > 0)
        let bytes = Array(text.utf8)
        guard bytes.count > maxBytes else { return [text] }
        var chunks: [String] = []
        var offset = 0
        while offset < bytes.count {
            var end = min(offset + maxBytes, bytes.count)
            if end < bytes.count {
                while end > offset, bytes[end] & 0b1100_0000 == 0b1000_0000 {
                    end -= 1
                }
            }
            if end == offset {
                end = min(offset + 4, bytes.count)
                while end < bytes.count, bytes[end] & 0b1100_0000 == 0b1000_0000 {
                    end += 1
                }
            }
            chunks.append(String(decoding: bytes[offset..<end], as: UTF8.self))
            offset = end
        }
        return chunks
    }

    nonisolated fileprivate static func defaultHandler(
        level: LogLevel,
        module: LogModule,
        message: String
    ) {
        if #available(iOS 14.0, macOS 11.0, *) {
            let logger = os.Logger(subsystem: sparkLogSubsystemStorage.value, category: module.rawValue)
            switch level {
            case .verbose:
                logger.trace("\(message, privacy: .public)")
            case .debug:
                logger.debug("\(message, privacy: .public)")
            case .info:
                logger.info("\(message, privacy: .public)")
            case .warning:
                logger.warning("\(message, privacy: .public)")
            case .error:
                logger.error("\(message, privacy: .public)")
            }
            return
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)][\(module.rawValue)][\(level.symbol)] \(message)")
    }
}

/// 轻量日志协议；每条日志单行，模块使用 `LogModule`。
nonisolated protocol Logger: Sendable {
    nonisolated func verbose(_ message: String, module: LogModule)
    nonisolated func debug(_ message: String, module: LogModule)
    nonisolated func info(_ message: String, module: LogModule)
    nonisolated func warning(_ message: String, module: LogModule)
    nonisolated func error(_ message: String, module: LogModule)
}

nonisolated extension Logger {
    func verbose(_ message: String) {
        verbose(message, module: .general)
    }

    func debug(_ message: String) {
        debug(message, module: .general)
    }

    /// 完整输出超长调试文本；普通 `debug` 经 os.Logger 时会被截成 `<…>`。
    func debugUntruncated(_ message: String, module: LogModule) {
        SparkLogger.debugUntruncated(message, module: module)
    }

    func info(_ message: String) {
        info(message, module: .general)
    }

    func warning(_ message: String) {
        warning(message, module: .general)
    }

    func error(_ message: String) {
        error(message, module: .general)
    }
}

nonisolated struct ConsoleLogger: Logger {
    nonisolated func verbose(_ message: String, module: LogModule) {
        SparkLogger.log(level: .verbose, module: module, message: message)
    }

    nonisolated func debug(_ message: String, module: LogModule) {
        SparkLogger.log(level: .debug, module: module, message: message)
    }

    nonisolated func info(_ message: String, module: LogModule) {
        SparkLogger.log(level: .info, module: module, message: message)
    }

    nonisolated func warning(_ message: String, module: LogModule) {
        SparkLogger.log(level: .warning, module: module, message: message)
    }

    nonisolated func error(_ message: String, module: LogModule) {
        SparkLogger.log(level: .error, module: module, message: message)
    }
}
