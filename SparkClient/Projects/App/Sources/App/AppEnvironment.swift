import Foundation

/// 统一管理运行环境，避免业务代码散落 `#if DEBUG`。
enum AppEnvironment: String, CaseIterable, Sendable {
    case debug
    case staging
    case production

    static let current: AppEnvironment = {
        #if DEBUG
        .debug
        #elseif STAGING
        .staging
        #else
        .production
        #endif
    }()

    var apiBaseURL: URL {
        switch self {
        case .debug:
            return URL(string: "http://172.169.5.114:8000")!
        case .staging:
            return URL(string: "https://api-staging.sparkclient.local")!
        case .production:
            return URL(string: "https://api.sparkclient.local")!
        }
    }

    var logLevel: LogLevel {
        switch self {
        case .debug, .staging:
            return .verbose
        case .production:
            return .error
        }
    }

    var subsystem: String {
        switch self {
        case .debug:
            return "SparkClient.Debug"
        case .staging:
            return "SparkClient.Staging"
        case .production:
            return "SparkClient"
        }
    }

    var ocrConfiguration: OCRConfiguration {
        switch self {
        case .debug:
            return OCRConfiguration(
                language: .codes(["zh-Hans", "en-US"]),
                useLanguageCorrection: true,
                enableAliyunOCR: false,
                enableLocalServerOCR: false,
                localServerBaseURL: apiBaseURL.absoluteString,
                localServerTimeoutMs: 15_000
            )
        case .staging:
            return OCRConfiguration(
                language: .codes(["zh-Hans", "en-US"]),
                useLanguageCorrection: true,
                enableAliyunOCR: true,
                enableLocalServerOCR: false,
                localServerBaseURL: apiBaseURL.absoluteString,
                localServerTimeoutMs: 12_000
            )
        case .production:
            return OCRConfiguration(
                language: .codes(["zh-Hans", "en-US"]),
                useLanguageCorrection: true,
                enableAliyunOCR: true,
                enableLocalServerOCR: false
            )
        }
    }
}
