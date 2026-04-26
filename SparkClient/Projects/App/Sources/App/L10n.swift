import Foundation

/// 集中管理文案 Key，避免 UI 层散落硬编码字符串。
enum L10n {
    static func text(_ key: String, fallback: String? = nil, comment: StaticString = "") -> String {
        _ = comment

        for localization in preferredLocalizations() {
            guard let bundlePath = Bundle.main.path(forResource: localization, ofType: "lproj"),
                  let bundle = Bundle(path: bundlePath) else {
                continue
            }
            let value = bundle.localizedString(forKey: key, value: "__MISSING__", table: nil)
            if value != "__MISSING__" {
                return value
            }
        }

        return fallback ?? key
    }

    static func homeGreeting(_ name: String) -> String {
        String(
            format: text("home.greeting"),
            locale: Locale.current,
            name
        )
    }

    private static func preferredLocalizations(locale: Locale = .current) -> [String] {
        var ordered: [String] = []
        let identifier = locale.identifier
        let languageCode = locale.languageCode?.lowercased() ?? "en"

        if identifier.hasPrefix("zh-Hans") || identifier.hasPrefix("zh_CN") || identifier.hasPrefix("zh-SG") {
            ordered.append("zh-Hans")
        } else if identifier.hasPrefix("zh-Hant") || identifier.hasPrefix("zh_TW") || identifier.hasPrefix("zh-HK") {
            ordered.append("zh-Hant")
        }

        ordered.append(languageCode)
        ordered.append("en")

        var deduped: [String] = []
        for item in ordered where deduped.contains(item) == false {
            deduped.append(item)
        }
        return deduped
    }
}
