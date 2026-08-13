import Foundation

/// 集中管理文案 Key，避免 UI 层散落硬编码字符串。
/// `nonisolated`：工程启用 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 时，仍允许域模型 / 合并逻辑在非 UI 隔离域读取文案。
nonisolated enum L10n {
    nonisolated static func text(_ key: String, fallback: String? = nil, comment: StaticString = "") -> String {
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

    /// 带占位符的本地化文案，统一使用 `Locale.current` 格式化。
    nonisolated static func format(
        _ key: String,
        fallback: String? = nil,
        comment: StaticString = "",
        _ args: CVarArg...
    ) -> String {
        String(
            format: text(key, fallback: fallback, comment: comment),
            locale: Locale.current,
            arguments: args
        )
    }

    /// 读取编号后缀的本地化数组，例如 `prefix.1`、`prefix.2`。
    nonisolated static func numberedTexts(prefix: String, count: Int) -> [String] {
        guard count > 0 else { return [] }
        return (1...count).map { index in
            text("\(prefix).\(index)")
        }
    }

    nonisolated static func homeGreeting(_ name: String) -> String {
        format("home.greeting", name)
    }

    private nonisolated static func preferredLocalizations(locale: Locale = .current) -> [String] {
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
