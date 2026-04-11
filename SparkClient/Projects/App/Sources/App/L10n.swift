import Foundation

/// 集中管理文案 Key，避免 UI 层散落硬编码字符串。
enum L10n {
    static func text(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .main)
    }

    static func homeGreeting(_ name: String) -> String {
        String(
            format: text("home.greeting"),
            locale: Locale.current,
            name
        )
    }
}
