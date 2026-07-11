import Foundation

/// 统一管理 AI 提示词本地化读取：
/// - 支持按当前 locale 自动匹配
/// - 缺失时回退英文，保证新增语言只需补 strings 资源
nonisolated struct AIPromptL10n: Sendable {
    nonisolated let locale: Locale

    nonisolated init(locale: Locale = .current) {
        self.locale = locale
    }

    nonisolated func prompt(_ key: String, fallback: String) -> String {
        localizedString(key: key, table: "Prompts", fallback: fallback)
    }

    /// `ToolPrompts` 使用稳定英文 key（如 `tool.summary.fetch_step_details`），各语言 lproj 提供译文。
    nonisolated func tool(_ key: String, fallback: String? = nil) -> String {
        localizedString(key: key, table: "ToolPrompts", fallback: fallback ?? key)
    }

    nonisolated func promptFormat(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        let template = prompt(key, fallback: fallback)
        return String(format: template, locale: locale, arguments: arguments)
    }

    /// 若当前 locale 资源中存在该 key 则返回值，否则返回 `nil`（不触发 fallback）。
    nonisolated func promptIfExists(_ key: String) -> String? {
        for localization in preferredLocalizations() {
            guard let bundlePath = Bundle.main.path(forResource: localization, ofType: "lproj"),
                  let bundle = Bundle(path: bundlePath) else {
                continue
            }
            let value = bundle.localizedString(forKey: key, value: "__MISSING__", table: "Prompts")
            if value != "__MISSING__" {
                return value
            }
        }
        return nil
    }

    nonisolated private func localizedString(key: String, table: String, fallback: String) -> String {
        for localization in preferredLocalizations() {
            guard let bundlePath = Bundle.main.path(forResource: localization, ofType: "lproj"),
                  let bundle = Bundle(path: bundlePath) else {
                continue
            }
            let value = bundle.localizedString(forKey: key, value: "__MISSING__", table: table)
            if value != "__MISSING__" {
                return value
            }
        }
        return fallback
    }

    nonisolated private func preferredLocalizations() -> [String] {
        var ordered: [String] = []
        let identifier = locale.identifier
        let languageCode = locale.languageCode?.lowercased() ?? "en"

        // zh-Hans / zh-Hant / en 等常见标识优先
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
