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
//            return URL(string: "https://api.dreamhua.top")!

            return URL(string: "http://175.178.12.93:2026")! //192.168.31.140 // localhost //172.20.10.2 //192.168.31.39  //172.169.8.88 // 192.168.31.128  // 192.168.31.38 //192.168.31.210
//            return URL(string: "https://api.dreamhua.top")! //192.168.31.140 // localhost //172.20.10.2 //192.168.31.39  //172.169.8.88 // 192.168.31.128  // 192.168.31.38 //192.168.31.192
        case .staging:
            return URL(string: "https://api.dreamhua.top")!
        case .production:
            return URL(string: "https://api.dreamhua.top")!
        }
    }

    /// 法律文档站点根地址（隐私政策、服务条款等非 API 页面）。
    var siteBaseURL: URL {
        let productionFallback = URL(string: "https://www.dreamhua.top")!
        guard var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false) else {
            return productionFallback
        }

        if let host = components.host {
            let isLocalDevHost = host == "localhost"
                || host.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
            if isLocalDevHost {
                return productionFallback
            }
            if host.hasPrefix("api.") {
                components.host = "www." + String(host.dropFirst(4))
            }
        }

        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url ?? productionFallback
    }

    /// 应用隐私政策页面。
    var privacyPolicyURL: URL {
        siteBaseURL.appendingPathComponent("legal/privacy/")
    }

    /// 应用服务条款页面。
    var termsOfServiceURL: URL {
        siteBaseURL.appendingPathComponent("legal/terms/")
    }

    var logLevel: LogLevel {
        switch self {
        case .debug, .staging:
            return .debug
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
