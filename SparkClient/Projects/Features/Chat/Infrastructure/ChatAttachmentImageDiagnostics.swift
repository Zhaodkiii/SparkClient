import Foundation

/// 聊天图片加载链路日志。
nonisolated enum ChatAttachmentImageDiagnostics {
    private static let logModule = LogModule.general
    private static let logger: Logger = ConsoleLogger()

    nonisolated static func debug(_ message: String) {
        logger.debug("[ChatImage] \(message)", module: logModule)
    }

    nonisolated static func info(_ message: String) {
        logger.info("[ChatImage] \(message)", module: logModule)
    }

    nonisolated static func warning(_ message: String) {
        logger.warning("[ChatImage] \(message)", module: logModule)
    }

    nonisolated static func error(_ message: String) {
        logger.error("[ChatImage] \(message)", module: logModule)
    }

    nonisolated static func errorDescription(_ error: Error) -> String {
        CodableDiagnostics.describe(error)
    }
}
