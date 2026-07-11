import Foundation

nonisolated enum SearchRuntimeConfigResolver {
    nonisolated static func resolve(from snapshot: AISettingsSnapshot) throws -> SearchRuntimeConfig {
        guard snapshot.searchToolPreferences.useSearch else {
            throw SearchRuntimeError.disabled
        }

        let candidates = snapshot.searchKeys
            .filter { $0.searchClass.lowercased() == "web" && $0.isUsing }
            .sorted {
                if $0.priority == $1.priority {
                    return $0.timestamp > $1.timestamp
                }
                return $0.priority > $1.priority
            }

        guard let active = candidates.first else {
            throw SearchRuntimeError.missingActiveProvider
        }
        guard let url = URL(string: active.requestURL), url.scheme != nil else {
            throw SearchRuntimeError.invalidEndpoint(active.requestURL)
        }

        let provider = SearchProviderID(company: active.company)
        let key = active.key.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider != .spark && key.isEmpty {
            throw SearchRuntimeError.missingAPIKey(active.name)
        }

        return SearchRuntimeConfig(
            provider: provider,
            displayName: active.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? active.company : active.name,
            apiKey: key,
            requestURL: url,
            searchCount: max(1, min(snapshot.searchToolPreferences.searchCount, 50)),
            bilingualSearch: snapshot.searchToolPreferences.bilingualSearch,
            revision: snapshot.searchConfigRevision,
            rawKeyID: active.id
        )
    }

    nonisolated static func normalizedHash(preferences: AISearchToolPreferences, searchKeys: [SearchKeys]) -> String {
        let keyRows = searchKeys
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                [
                    $0.id.uuidString,
                    $0.name,
                    $0.company,
                    stableHash($0.key),
                    $0.requestURL,
                    "\($0.isUsing)",
                    $0.searchClass,
                    $0.authType.rawValue,
                    "\($0.priority)",
                    $0.enabledScopes.sorted().joined(separator: ","),
                    "\($0.revision)"
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
        let source = [
            "\(preferences.useSearch)",
            "\(preferences.bilingualSearch)",
            "\(preferences.searchCount)",
            keyRows
        ].joined(separator: "\n")
        return stableHash(source)
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
