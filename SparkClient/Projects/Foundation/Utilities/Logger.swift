import Foundation

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

    nonisolated fileprivate static func defaultHandler(
        level: LogLevel,
        module: LogModule,
        message: String
    ) {
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
    nonisolated func debug(_ message: String, module: LogModule)
    nonisolated func info(_ message: String, module: LogModule)
    nonisolated func warning(_ message: String, module: LogModule)
    nonisolated func error(_ message: String, module: LogModule)
}

nonisolated extension Logger {
    func debug(_ message: String) {
        debug(message, module: .general)
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
