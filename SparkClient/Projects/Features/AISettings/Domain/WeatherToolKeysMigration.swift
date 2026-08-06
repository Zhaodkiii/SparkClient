import Foundation

/// 天气 ToolKeys 种子补齐、company 归一化与 WEATHERKIT → APPLEWEATHER 迁移。
nonisolated enum WeatherToolKeysMigration {
    static let requiredCompanies = ["QWEATHER", "OPENWEATHER", "APPLEWEATHER"]

    nonisolated static var seedWeatherToolKeys: [ToolKeys] {
        AISettingsDefaults.toolKeys.filter { $0.toolClass.lowercased() == "weather" }
    }

    nonisolated static func canonicalCompany(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "OPENWEATHER", "OPENWEATHERMAP", "OPEN_WEATHER":
            return "OPENWEATHER"
        case "QWEATHER", "QWEATHER_KEY":
            return "QWEATHER"
        case "APPLEWEATHER", "WEATHERKIT", "APPLE_WEATHER":
            return "APPLEWEATHER"
        default:
            return nil
        }
    }

    nonisolated static func displayName(for key: ToolKeys) -> String {
        switch canonicalCompany(key.company) {
        case "QWEATHER":
            return L10n.text("ai_settings.weather.provider.qweather", fallback: "QWeather")
        case "OPENWEATHER":
            return L10n.text("ai_settings.weather.provider.openweather", fallback: "OpenWeather")
        case "APPLEWEATHER":
            return L10n.text("ai_settings.weather.provider.apple_weather", fallback: "Apple Weather")
        default:
            let trimmed = key.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? key.company : trimmed
        }
    }

    nonisolated static func reconcile(toolKeys: [ToolKeys]) -> [ToolKeys] {
        var nonWeather = toolKeys.filter { $0.toolClass.lowercased() != "weather" }
        let weatherEntries = toolKeys.filter { $0.toolClass.lowercased() == "weather" }

        var mergedByCompany: [String: ToolKeys] = [:]
        for entry in weatherEntries {
            guard let company = canonicalCompany(entry.company) else { continue }
            if let existing = mergedByCompany[company] {
                mergedByCompany[company] = pickPreferred(existing: existing, incoming: entry, company: company)
            } else {
                mergedByCompany[company] = normalize(entry, company: company)
            }
        }

        for seed in seedWeatherToolKeys {
            guard let company = canonicalCompany(seed.company) else { continue }
            if let existing = mergedByCompany[company] {
                mergedByCompany[company] = backfillMissingFields(existing: existing, seed: seed, company: company)
            } else {
                mergedByCompany[company] = seed
            }
        }

        for company in requiredCompanies {
            guard var key = mergedByCompany[company] else { continue }
            if company == "APPLEWEATHER",
               let provider = WeatherProviderID.parse(company: company),
               provider.hasLocalAdapter == false {
                key.isUsing = false
            }
            mergedByCompany[company] = key
        }

        let orderedWeather = requiredCompanies.compactMap { mergedByCompany[$0] }
        nonWeather.append(contentsOf: orderedWeather)
        return nonWeather
    }

    nonisolated private static func normalize(_ key: ToolKeys, company: String) -> ToolKeys {
        var normalized = key
        normalized.company = company
        normalized.toolClass = "weather"
        if normalized.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.name = seedName(for: company)
        }
        if normalized.help.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.help = seedHelp(for: company)
        }
        return normalized
    }

    nonisolated private static func pickPreferred(
        existing: ToolKeys,
        incoming: ToolKeys,
        company: String
    ) -> ToolKeys {
        let lhsScore = preferenceScore(existing)
        let rhsScore = preferenceScore(incoming)
        let winner: ToolKeys
        if lhsScore == rhsScore {
            winner = existing.timestamp >= incoming.timestamp ? existing : incoming
        } else {
            winner = lhsScore > rhsScore ? existing : incoming
        }
        let loser = winner.id == existing.id ? incoming : existing
        var merged = normalize(winner, company: company)
        if merged.help.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           loser.help.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            merged.help = loser.help
        } else if merged.help.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.help = seedHelp(for: company)
        }
        if merged.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           loser.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            merged.key = loser.key
        }
        if merged.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           loser.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            merged.requestURL = loser.requestURL
        }
        return merged
    }

    nonisolated private static func backfillMissingFields(
        existing: ToolKeys,
        seed: ToolKeys,
        company: String
    ) -> ToolKeys {
        var merged = normalize(existing, company: company)
        if merged.help.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.help = seed.help
        }
        if merged.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.requestURL = seed.requestURL
        }
        return merged
    }

    nonisolated private static func preferenceScore(_ key: ToolKeys) -> Int {
        var score = 0
        if key.isUsing { score += 16 }
        if key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { score += 8 }
        if key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { score += 4 }
        if canonicalCompany(key.company) == key.company.uppercased() { score += 2 }
        return score
    }

    nonisolated private static func seedName(for company: String) -> String {
        switch company {
        case "QWEATHER": return "QWEATHER_KEY"
        case "OPENWEATHER": return "OPENWEATHER_KEY"
        case "APPLEWEATHER": return "APPLEWEATHER_KEY"
        default: return company
        }
    }

    nonisolated private static func seedHelp(for company: String) -> String {
        seedWeatherToolKeys.first { canonicalCompany($0.company) == company }?.help ?? ""
    }
}
