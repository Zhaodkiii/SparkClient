import Foundation

nonisolated enum WeatherRuntimeConfigResolver {
    nonisolated static func activeWeatherKey(from snapshot: AISettingsSnapshot) -> ToolKeys? {
        rankedWeatherCandidates(from: snapshot.toolKeys).first
    }

    nonisolated static func resolve(from snapshot: AISettingsSnapshot) throws -> WeatherRuntimeConfig {
        guard snapshot.weatherToolPreferences.useWeather else {
            throw WeatherRuntimeError.disabled
        }

        guard let active = activeWeatherKey(from: snapshot) else {
            throw WeatherRuntimeError.missingActiveProvider
        }

        guard let provider = WeatherProviderID.parse(company: active.company) else {
            throw WeatherRuntimeError.unsupportedProvider(active.company)
        }
        guard provider.hasLocalAdapter else {
            throw WeatherRuntimeError.unsupportedProvider(provider.rawValue)
        }

        let requestURL = WeatherEndpointNormalizer.normalizedBaseURL(
            requestURL: active.requestURL,
            provider: provider
        )

        let key = active.key.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.usesAPIKey {
            if key.isEmpty {
                throw WeatherRuntimeError.missingAPIKey(active.name)
            }
            if WeatherEndpointNormalizer.isValidEndpoint(requestURL: active.requestURL, provider: provider) == false {
                throw WeatherRuntimeError.invalidEndpoint(active.requestURL)
            }
        }

        return WeatherRuntimeConfig(
            provider: provider,
            displayName: active.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? active.company : active.name,
            apiKey: key,
            requestURL: requestURL,
            revision: snapshot.weatherConfigRevision,
            rawKeyID: active.id
        )
    }

    nonisolated static func normalizedHash(
        preferences: AIWeatherToolPreferences,
        toolKeys: [ToolKeys]
    ) -> String {
        let keyRows = toolKeys
            .filter { $0.toolClass.lowercased() == "weather" }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                [
                    $0.id.uuidString,
                    $0.name,
                    $0.company,
                    stableHash($0.key),
                    $0.requestURL,
                    "\($0.isUsing)",
                    $0.toolClass,
                    "\($0.timestamp.timeIntervalSince1970)"
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
        let source = [
            "\(preferences.useWeather)",
            keyRows
        ].joined(separator: "\n")
        return stableHash(source)
    }

    nonisolated static func normalizedHash(toolKeys: [ToolKeys]) -> String {
        normalizedHash(preferences: AIWeatherToolPreferences(), toolKeys: toolKeys)
    }

    nonisolated private static func rankedWeatherCandidates(from toolKeys: [ToolKeys]) -> [ToolKeys] {
        toolKeys
            .filter { $0.toolClass.lowercased() == "weather" && $0.isUsing }
            .sorted { $0.timestamp > $1.timestamp }
    }

    nonisolated private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}
