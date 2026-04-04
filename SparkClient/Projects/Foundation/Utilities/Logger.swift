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
    _ category: String,
    _ message: String,
    _ file: String?,
    _ function: String?,
    _ line: UInt
) -> Void

nonisolated(unsafe) private let sparkLogLevelStorage = Atomic<LogLevel>(.info)
nonisolated(unsafe) private let sparkLogHandlerStorage = Atomic<InternalLogHandler>(SparkLogger.defaultHandler)
nonisolated(unsafe) private let sparkLogSubsystemStorage = Atomic<String>("SparkClient")

/// 网络与基础设施统一日志中心。
/// 设计参考 purchases-ios 的 Logger：
/// 1. 全局可调日志级别
/// 2. 统一 handler
/// 3. 运行时可配置
enum SparkLogger {
    nonisolated static var logLevel: LogLevel {
        get { sparkLogLevelStorage.value }
        set { sparkLogLevelStorage.value = newValue }
    }

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
        category: String,
        message: String,
        file: String? = nil,
        function: String? = nil,
        line: UInt = #line
    ) {
        guard isEnabled(level) else { return }
        sparkLogHandlerStorage.value(level, category, message, file, function, line)
    }

    nonisolated fileprivate static func defaultHandler(
        level: LogLevel,
        category: String,
        message: String,
        file: String?,
        function: String?,
        line: UInt
    ) {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let subsystem = SparkLogger.subsystem
        let location: String
        if let file {
            let functionPart = function.map { " \($0)" } ?? ""
            location = " (\(file):\(line)\(functionPart))"
        } else {
            location = ""
        }

        print("[\(timestamp)][\(subsystem)][\(level.symbol)][\(category)] \(message)\(location)")
    }
}

/// 兼容当前项目的轻量日志协议。
/// 默认 category 为 `general`，也支持显式传入分类。
nonisolated protocol Logger: Sendable {
    nonisolated func debug(_ message: String, category: String, file: StaticString?, function: StaticString?, line: UInt)
    nonisolated func info(_ message: String, category: String, file: StaticString?, function: StaticString?, line: UInt)
    nonisolated func warning(_ message: String, category: String, file: StaticString?, function: StaticString?, line: UInt)
    nonisolated func error(_ message: String, category: String, file: StaticString?, function: StaticString?, line: UInt)
}

nonisolated extension Logger {
    func debug(
        _ message: String,
        category: String = "general",
        file: StaticString? = #fileID,
        function: StaticString? = #function,
        line: UInt = #line
    ) {
        debug(message, category: category, file: file, function: function, line: line)
    }

    func info(
        _ message: String,
        category: String = "general",
        file: StaticString? = #fileID,
        function: StaticString? = #function,
        line: UInt = #line
    ) {
        info(message, category: category, file: file, function: function, line: line)
    }

    func warning(
        _ message: String,
        category: String = "general",
        file: StaticString? = #fileID,
        function: StaticString? = #function,
        line: UInt = #line
    ) {
        warning(message, category: category, file: file, function: function, line: line)
    }

    func error(
        _ message: String,
        category: String = "general",
        file: StaticString? = #fileID,
        function: StaticString? = #function,
        line: UInt = #line
    ) {
        error(message, category: category, file: file, function: function, line: line)
    }
}

nonisolated struct ConsoleLogger: Logger {
    nonisolated func debug(_ message: String, category: String, file: StaticString?, function: StaticString?, line: UInt) {
        SparkLogger.log(
            level: .debug,
            category: category,
            message: message,
            file: file.map { "\($0)" },
            function: function.map { "\($0)" },
            line: line
        )
    }

    nonisolated func info(_ message: String, category: String, file: StaticString?, function: StaticString?, line: UInt) {
        SparkLogger.log(
            level: .info,
            category: category,
            message: message,
            file: file.map { "\($0)" },
            function: function.map { "\($0)" },
            line: line
        )
    }

    nonisolated func warning(_ message: String, category: String, file: StaticString?, function: StaticString?, line: UInt) {
        SparkLogger.log(
            level: .warning,
            category: category,
            message: message,
            file: file.map { "\($0)" },
            function: function.map { "\($0)" },
            line: line
        )
    }

    nonisolated func error(_ message: String, category: String, file: StaticString?, function: StaticString?, line: UInt) {
        SparkLogger.log(
            level: .error,
            category: category,
            message: message,
            file: file.map { "\($0)" },
            function: function.map { "\($0)" },
            line: line
        )
    }
}
