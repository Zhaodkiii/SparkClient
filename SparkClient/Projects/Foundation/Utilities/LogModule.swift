import Foundation

/// 统一日志模块标识（大写英文，下划线风格与控制台输出一致）。
enum LogModule: String, Sendable, CaseIterable {
    case network = "NETWORK"
    case medical = "MEDICAL"
    case aiConfig = "AI_CONFIG"
    case cache = "CACHE"
    case oss = "OSS"
    case auth = "AUTH"
    case home = "HOME"
    case camera = "CAMERA"
    case nutrition = "NUTRITION"
    case fitness = "FITNESS"
    case general = "GENERAL"
    case push = "PUSH"
    case deepTutorChat = "DEEP_TUTOR_CHAT"
}

/// 长文本日志安全截断（OCR、JSON、调试摘要等）。
enum LogMessageSanitizer: Sendable {
    /// 与 OpenAI 网关等截断逻辑共用的默认上限。
    static let maxLogSnippetLength = 200

    /// 单行化并截断，避免日志刷屏或泄露长内容。
    nonisolated static func singleLineSnippet(_ text: String, limit: Int = 200) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        guard collapsed.count > limit else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: limit, limitedBy: collapsed.endIndex) ?? collapsed.endIndex
        return String(collapsed[..<end]) + "…(len=\(collapsed.count))"
    }
}
